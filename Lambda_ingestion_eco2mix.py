
import json
import os
import urllib.request
import urllib.parse
from datetime import datetime, timedelta, timezone

import boto3

s3 = boto3.client("s3")

BUCKET = os.environ["BRONZE_BUCKET"]

# Les identifiants des datasets sont configurables
DATASETS = {
    "national-realtime": os.environ["RTE_REALTIME_DATASET"],
    "national-consolidated": os.environ["RTE_CONSOLIDATED_DATASET"],
    "regional": os.environ["RTE_REGIONAL_DATASET"]
}

API_BASE = "https://odre.opendatasoft.com/api/explore/v2.1/catalog/datasets"


def lambda_handler(event, context):

    dataset_name = event["dataset"]

    if dataset_name not in DATASETS:
        raise ValueError(f"Unknown dataset: {dataset_name}")

    dataset_id = DATASETS[dataset_name]

    limit = 100
    offset = 0
    total_records = 0

    ingestion_time = datetime.now(timezone.utc)
    ingestion_date = ingestion_time.strftime("%Y-%m-%d")

    # Seulement les 2 derniers jours : sans filtre, on relit tout le jeu de données
    since = (ingestion_time - timedelta(days=2)).strftime("%Y-%m-%d")

    while True:

        params = urllib.parse.urlencode({
            "where": f"date_heure >= '{since}'",
            "order_by": "date_heure",
            "limit": limit,
            "offset": offset
        })

        url = (
            f"{API_BASE}/{dataset_id}/records?"
            f"{params}"
        )

        request = urllib.request.Request(
            url,
            headers={"Accept": "application/json"}
        )

        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))

        records = payload.get("results", [])

        if not records:
            break

        # Conservation de la réponse API brute
        s3_key = (
            f"rte/eco2mix/{dataset_name}/"
            f"ingestion_date={ingestion_date}/"
            f"part-{offset}.json"
        )

        s3.put_object(
            Bucket=BUCKET,
            Key=s3_key,
            Body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            ContentType="application/json"
        )

        total_records += len(records)
        offset += limit

        if offset >= payload.get("total_count", 0):
            break

    return {
        "status": "SUCCESS",
        "source": "RTE",
        "dataset": dataset_name,
        "records": total_records,
        "bucket": BUCKET,
        "ingestion_date": ingestion_date
    }
