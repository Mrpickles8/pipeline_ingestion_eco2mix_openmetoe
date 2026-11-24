
import os
import time

import boto3

client = boto3.client("redshift-data")

CLUSTER_ID = os.environ["CLUSTER_ID"]
DATABASE = os.environ["DATABASE"]
SECRET_ARN = os.environ["SECRET_ARN"]
COPY_ROLE_ARN = os.environ["COPY_ROLE_ARN"]
GOLD_BUCKET = os.environ["GOLD_BUCKET"]

# Quel job a réussi -> quelle table charger, depuis quel dossier du gold
TABLES = {
    os.environ["JOB_ECO2MIX"]: {
        "table": "public.eco2mix",
        "gold_path": f"s3://{GOLD_BUCKET}/gold/energy/national-realtime/"
    },
    os.environ["JOB_OPENMETEO"]: {
        "table": "public.weather_forecast",
        "gold_path": f"s3://{GOLD_BUCKET}/gold/weather/forecast/"
    }
}


def lambda_handler(event, context):

    # EventBridge envoie le nom du job Glue qui vient de réussir
    job_name = event["detail"]["jobName"]

    if job_name not in TABLES:
        raise ValueError(f"Unknown job: {job_name}")

    table = TABLES[job_name]["table"]
    gold_path = TABLES[job_name]["gold_path"]

    # On vide la table puis on recharge tout le gold.
    # Les 2 requêtes passent dans une seule transaction :
    # si le COPY échoue, le DELETE est annulé et la table garde ses données.
    sqls = [
        f"DELETE FROM {table};",
        f"COPY {table} FROM '{gold_path}' "
        f"IAM_ROLE '{COPY_ROLE_ARN}' FORMAT AS PARQUET;"
    ]

    response = client.batch_execute_statement(
        ClusterIdentifier=CLUSTER_ID,
        Database=DATABASE,
        SecretArn=SECRET_ARN,
        Sqls=sqls
    )

    statement_id = response["Id"]

    # La Data API répond tout de suite : on attend la fin du COPY
    while True:
        status = client.describe_statement(Id=statement_id)

        if status["Status"] == "FINISHED":
            break

        if status["Status"] in ["FAILED", "ABORTED"]:
            raise RuntimeError(f"COPY failed: {status.get('Error')}")

        time.sleep(5)

    return {
        "status": "SUCCESS",
        "job": job_name,
        "table": table,
        "source": gold_path,
        "statement_id": statement_id
    }
