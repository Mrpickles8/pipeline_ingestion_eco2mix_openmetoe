
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
        "SILVER_PATH",
        "GOLD_PATH"
    ]
)

SOURCE = args["SOURCE"].lower()
DATASET = args["DATASET"]
SILVER_PATH = args["SILVER_PATH"]
GOLD_PATH = args["GOLD_PATH"]

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Réécrit seulement les jours présents dans les données (pas de doublons si on relance)
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

df = (
    spark.read
    .format("parquet")
    .load(SILVER_PATH)
    .filter(F.col("dataset") == DATASET)
)

if SOURCE == "rte":

    # Production renouvelable
    df = df.withColumn(
        "renewable_generation_mw",
        F.coalesce(F.col("eolien"), F.lit(0))
        + F.coalesce(F.col("solaire"), F.lit(0))
        + F.coalesce(F.col("hydraulique"), F.lit(0))
        + F.coalesce(F.col("bioenergies"), F.lit(0))
    )

    # Production thermique
    df = df.withColumn(
        "thermal_generation_mw",
        F.coalesce(F.col("gaz"), F.lit(0))
        + F.coalesce(F.col("charbon"), F.lit(0))
        + F.coalesce(F.col("fioul"), F.lit(0))
    )

    # Erreur de prévision de consommation
    df = df.withColumn(
        "consumption_forecast_error_mw",
        F.col("consommation") - F.col("prevision_j1")
    )

    # Part renouvelable
    df = df.withColumn(
        "renewable_share",
        F.when(
            F.col("renewable_generation_mw")
            + F.coalesce(F.col("nucleaire"), F.lit(0))
            + F.coalesce(F.col("thermal_generation_mw"), F.lit(0)) > 0,
            F.col("renewable_generation_mw") /
            (
                F.col("renewable_generation_mw")
                + F.coalesce(F.col("nucleaire"), F.lit(0))
                + F.coalesce(F.col("thermal_generation_mw"), F.lit(0))
            )
        )
    )

    # Colonnes dans le même ordre que la table Redshift : le COPY lit par position
    df = df.select(
        "event_timestamp",
        "perimetre",
        "consommation",
        "prevision_j1",
        "nucleaire",
        "eolien",
        "solaire",
        "renewable_generation_mw",
        "thermal_generation_mw",
        "consumption_forecast_error_mw",
        "renewable_share",
        "event_date"
    )

    target = f"{GOLD_PATH}/energy/{DATASET}/"

elif SOURCE == "openmeteo":

    # Indicateurs météo
    if "wind_speed_100m" in df.columns:
        df = df.withColumn(
            "wind_speed_100m",
            F.col("wind_speed_100m").cast("double")
        )

    if "shortwave_radiation" in df.columns:
        df = df.withColumn(
            "solar_radiation",
            F.col("shortwave_radiation").cast("double")
        )

    # Colonnes dans le même ordre que la table Redshift : le COPY lit par position
    df = df.select(
        "event_timestamp",
        "location",
        F.col("temperature_2m").cast("double"),
        F.col("precipitation").cast("double"),
        F.col("cloud_cover").cast("double"),
        F.col("wind_speed_100m").cast("double"),
        F.col("solar_radiation").cast("double"),
        "event_date"
    )

    target = f"{GOLD_PATH}/weather/{DATASET}/"

else:
    raise ValueError(f"Unsupported source: {SOURCE}")

# Écriture des données analytiques
(
    df.write
    .mode("overwrite")
    .format("parquet")
    .partitionBy("event_date")
    .save(target)
)

print(f"Gold processing completed: {SOURCE}/{DATASET}")
