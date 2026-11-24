
import json
import os
import urllib.request
import urllib.parse
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")

BUCKET = os.environ["BRONZE_BUCKET"]

LOCATIONS = {
    "geneva": {
        "latitude": 46.2044,
        "longitude": 6.1432,
        "country": "CH"
    },
    "lausanne": {
        "latitude": 46.5197,
        "longitude": 6.6323,
        "country": "CH"
    },
    "bern": {
        "latitude": 46.9480,
        "longitude": 7.4474,
        "country": "CH"
    },
    "basel": {
        "latitude": 47.5596,
        "longitude": 7.5886,
        "country": "CH"
    },
    "zurich": {
        "latitude": 47.3769,
        "longitude": 8.5417,
        "country": "CH"
    },
    "lugano": {
        "latitude": 46.0037,
        "longitude": 8.9511,
        "country": "CH"
    }
}

VARIABLES = [
    "temperature_2m",
    "relative_humidity_2m",
    "apparent_temperature",
    "precipitation",
    "cloud_cover",
    "wind_speed_10m",
    "wind_speed_100m",
    "wind_direction_10m",
    "wind_gusts_10m",
    "shortwave_radiation",
    "direct_radiation",
    "diffuse_radiation"
]


def lambda_handler(event, context):

    ingestion_date = datetime.now(
        timezone.utc
    ).strftime("%Y-%m-%d")

    results = []

    for city, coordinates in LOCATIONS.items():

        params = {
            "latitude": coordinates["latitude"],
            "longitude": coordinates["longitude"],
            "hourly": ",".join(VARIABLES),
            "forecast_days": 7,
            "timezone": "UTC",
            "wind_speed_unit": "kmh"
        }

        url = (
            "https://api.open-meteo.com/v1/forecast?"
            + urllib.parse.urlencode(params)
        )

        request = urllib.request.Request(
            url,
            headers={"Accept": "application/json"}
        )

        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))

        # Conservation de la réponse API brute
        key = (
            f"open-meteo/forecast/"
            f"country={coordinates['country']}/"
            f"location={city}/"
            f"ingestion_date={ingestion_date}/"
            f"forecast.json"
        )

        s3.put_object(
            Bucket=BUCKET,
            Key=key,
            Body=json.dumps(payload).encode("utf-8"),
            ContentType="application/json"
        )

        results.append({
            "location": city,
            "s3_key": key
        })

    return {
        "status": "SUCCESS",
        "source": "OPEN_METEO",
        "datasets": results,
        "ingestion_date": ingestion_date
    }
