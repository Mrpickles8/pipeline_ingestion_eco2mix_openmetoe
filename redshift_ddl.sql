
CREATE TABLE IF NOT EXISTS public.eco2mix (
    event_timestamp               TIMESTAMP,
    perimetre                     VARCHAR(64),
    consommation                  DOUBLE PRECISION,
    prevision_j1                  DOUBLE PRECISION,
    nucleaire                     DOUBLE PRECISION,
    eolien                        DOUBLE PRECISION,
    solaire                       DOUBLE PRECISION,
    renewable_generation_mw       DOUBLE PRECISION,
    thermal_generation_mw         DOUBLE PRECISION,
    consumption_forecast_error_mw DOUBLE PRECISION,
    renewable_share               DOUBLE PRECISION
)
SORTKEY (event_timestamp);

CREATE TABLE IF NOT EXISTS public.weather_forecast (
    event_timestamp TIMESTAMP,
    location        VARCHAR(64),
    temperature_2m  DOUBLE PRECISION,
    precipitation   DOUBLE PRECISION,
    cloud_cover     DOUBLE PRECISION,
    wind_speed_100m DOUBLE PRECISION,
    solar_radiation DOUBLE PRECISION
)
SORTKEY (event_timestamp);
