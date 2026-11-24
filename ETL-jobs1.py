
import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from pyspark.sql import functions as F

args = getResolvedOptions(
    sys.argv,
    [
        "SOURCE",
        "DATASET",
        "BRONZE_PATH",
        "SILVER_PATH"
    ]
)

SOURCE = args["SOURCE"].lower()
DATASET = args["DATASET"]
BRONZE_PATH = args["BRONZE_PATH"]
SILVER_PATH = args["SILVER_PATH"]

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Réécrit seulement les jours présents dans les données (pas de doublons si on relance)
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

# Lecture des données brutes
df = (
    spark.read
    .option("multiLine", "true")
    .json(BRONZE_PATH)
)

if SOURCE == "rte":

    # Extraction du tableau results de l'API ODRÉ
    df = df.select(
        F.explode("results").alias("record")
    ).select("record.*")

    df = df.withColumn(
        "source",
        F.lit("RTE")
    ).withColumn(
        "dataset",
        F.lit(DATASET)
    )

    if "date_heure" in df.columns:
        df = df.withColumn(
            "event_timestamp",
            F.to_timestamp("date_heure")
        )

    # Conversion automatique des colonnes numériques
    for column in df.columns:
        if column not in [
            "source",
            "dataset",
            "perimetre",
            "nature",
            "date",
            "heure",
            "date_heure",
            "event_timestamp"
        ]:
            df = df.withColumn(
                column,
                F.col(column).cast("double")
            )

    # Déduplication sur le périmètre et le timestamp
    if "event_timestamp" in df.columns:
        df = df.dropDuplicates([
            "perimetre",
            "event_timestamp"
        ])

elif SOURCE == "openmeteo":

    # Extraction des tableaux horaires
    hourly_columns = df.schema["hourly"].dataType.fieldNames()

    variable_columns = [
        column for column in hourly_columns
        if column != "time"
    ]

    # Associer chaque timestamp à ses variables météo
    zipped = F.arrays_zip(
        *[
            F.col(f"hourly.{column}")
            for column in ["time"] + variable_columns
        ]
    )

    df = df.select(
        F.explode(zipped).alias("weather")
    )

    df = df.select(
        *[
            F.col(f"weather.{column}").alias(column)
            for column in ["time"] + variable_columns
        ]
    )

    df = df.withColumn(
        "event_timestamp",
        F.to_timestamp("time")
    ).withColumn(
        "source",
        F.lit("OPEN_METEO")
    ).withColumn(
        "dataset",
        F.lit(DATASET)
    ).withColumn(
        "location",
        F.regexp_extract(
            F.input_file_name(),
            r"location=([^/]+)",
            1
        )
    )

    df = df.drop("time")

    df = df.dropDuplicates([
        "location",
        "event_timestamp"
    ])

else:
    raise ValueError(f"Unsupported source: {SOURCE}")

# Ajout de la date d'événement pour partitionnement
df = df.withColumn(
    "event_date",
    F.to_date("event_timestamp")
)

# Écriture Silver au format Parquet
(
    df.write
    .mode("overwrite")
    .format("parquet")
    .partitionBy("event_date")
    .save(SILVER_PATH)
)

print(f"Silver processing completed: {SOURCE}/{DATASET}")
