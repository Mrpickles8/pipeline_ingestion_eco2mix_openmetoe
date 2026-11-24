resource "aws_glue_catalog_database" "CatalogDatabaseGlue" {
  name = "databaseglue" # Glue met les noms en minuscules
}

####################
# Bucket des scripts Glue et du dossier temporaire 

resource "aws_s3_bucket" "glue_scripts" {
  bucket = "glue-scripts-${random_id.suffix.hex}"

  tags = {
    Name        = "My Glue scripts bucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_public_access_block" "glue_scripts" {
  bucket = aws_s3_bucket.glue_scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

####################
# Clé KMS 

resource "aws_kms_key" "key_glue_logs" {
  description             = "This key is for the Glue logs in CloudWatch"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "KeyAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = local.kms_admin_actions
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"
          }
        }
      }
    ]
  })
}


resource "aws_glue_security_configuration" "glue_logs_encryption" {
  name = "glue-logs-encryption"

  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn                = aws_kms_key.key_glue_logs.arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "DISABLED"
    }

    s3_encryption {
      s3_encryption_mode = "DISABLED"
    }
  }
}

####################
# Tables

resource "aws_glue_catalog_table" "silver_eco2mix" {
  name          = "silver_eco2mix"
  database_name = aws_glue_catalog_database.CatalogDatabaseGlue.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"               = "parquet"
    "projection.enabled"           = "true"
    "projection.event_date.type"   = "date"
    "projection.event_date.format" = "yyyy-MM-dd"
    "projection.event_date.range"  = "2026-01-01,NOW"
    "storage.location.template"    = "s3://${aws_s3_bucket.Silver_bucket.id}/silver/eco2mix/national-realtime/event_date=$${event_date}/"
  }

  partition_keys {
    name = "event_date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.Silver_bucket.id}/silver/eco2mix/national-realtime/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "event_timestamp"
      type = "timestamp"
    }
    columns {
      name = "perimetre"
      type = "string"
    }
    columns {
      name = "nature"
      type = "string"
    }
    columns {
      name = "consommation"
      type = "double"
    }
    columns {
      name = "nucleaire"
      type = "double"
    }
    columns {
      name = "eolien"
      type = "double"
    }
    columns {
      name = "solaire"
      type = "double"
    }
    columns {
      name = "dataset"
      type = "string"
    }
    columns {
      name = "source"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "gold_eco2mix" {
  name          = "gold_eco2mix"
  database_name = aws_glue_catalog_database.CatalogDatabaseGlue.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"               = "parquet"
    "projection.enabled"           = "true"
    "projection.event_date.type"   = "date"
    "projection.event_date.format" = "yyyy-MM-dd"
    "projection.event_date.range"  = "2026-01-01,NOW"
    "storage.location.template"    = "s3://${aws_s3_bucket.Gold_bucket.id}/gold/energy/national-realtime/event_date=$${event_date}/"
  }

  partition_keys {
    name = "event_date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.Gold_bucket.id}/gold/energy/national-realtime/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "event_timestamp"
      type = "timestamp"
    }
    columns {
      name = "perimetre"
      type = "string"
    }
    columns {
      name = "consommation"
      type = "double"
    }
    columns {
      name = "prevision_j1"
      type = "double"
    }
    columns {
      name = "nucleaire"
      type = "double"
    }
    columns {
      name = "eolien"
      type = "double"
    }
    columns {
      name = "solaire"
      type = "double"
    }
    columns {
      name = "renewable_generation_mw"
      type = "double"
    }
    columns {
      name = "thermal_generation_mw"
      type = "double"
    }
    columns {
      name = "consumption_forecast_error_mw"
      type = "double"
    }
    columns {
      name = "renewable_share"
      type = "double"
    }
  }
}

####################
# Jobs

resource "aws_glue_job" "etl_job_1" {
  name                   = "Job-Bronze-to-Silver"
  description            = "The job that transform bronze data to silver"
  role_arn               = aws_iam_role.glue_job_role_1.arn
  glue_version           = "5.0"
  max_retries            = 0
  timeout                = 10
  number_of_workers      = 2
  worker_type            = "G.1X"
  execution_class        = "STANDARD"
  security_configuration = aws_glue_security_configuration.glue_logs_encryption.name

  command {
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/jobs/ETL-jobs1.py"
    name            = "glueetl"
    python_version  = "3"
  }

  notification_property {
    notify_delay_after = 3 #
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--continuous-log-logGroup"          = "/aws-glue/jobs/eCO2mixJobs1"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${aws_s3_bucket.glue_scripts.id}/glue-temp/"
    "--SOURCE"                           = "rte"
    "--DATASET"                          = "national-realtime"
    "--BRONZE_PATH"                      = "s3://${aws_s3_bucket.Bronze_bucket.id}/rte/eco2mix/national-realtime/"
    "--SILVER_PATH"                      = "s3://${aws_s3_bucket.Silver_bucket.id}/silver/eco2mix/national-realtime/"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    "ManagedBy" = "AWS"
  }
}

resource "aws_s3_object" "glue_etl_script_1" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "jobs/ETL-jobs1.py"
  source = "${path.module}/ETL-jobs1.py"
  etag   = filemd5("${path.module}/ETL-jobs1.py")
}

resource "aws_glue_job" "etl_job_2" {
  name                   = "Job-Silver-to-Gold"
  description            = "The job that transform silver data to gold"
  role_arn               = aws_iam_role.glue_job_role_2.arn
  glue_version           = "5.0"
  max_retries            = 0
  timeout                = 10
  number_of_workers      = 2
  worker_type            = "G.1X"
  execution_class        = "STANDARD"
  security_configuration = aws_glue_security_configuration.glue_logs_encryption.name

  command {
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/jobs/ETL-jobs2.py"
    name            = "glueetl"
    python_version  = "3"
  }

  notification_property {
    notify_delay_after = 3 #
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--continuous-log-logGroup"          = "/aws-glue/jobs/eCO2mixJobs2"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${aws_s3_bucket.glue_scripts.id}/glue-temp/"
    "--SOURCE"                           = "rte"
    "--DATASET"                          = "national-realtime"
    "--SILVER_PATH"                      = "s3://${aws_s3_bucket.Silver_bucket.id}/silver/eco2mix/national-realtime/"
    "--GOLD_PATH"                        = "s3://${aws_s3_bucket.Gold_bucket.id}/gold"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    "ManagedBy" = "AWS"
  }
}

resource "aws_s3_object" "glue_etl_script_2" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "jobs/ETL-jobs2.py"
  source = "${path.module}/ETL-jobs2.py"
  etag   = filemd5("${path.module}/ETL-jobs2.py")
}

####################
# Workflow 
resource "aws_glue_workflow" "eco2mix_workflow" {
  name        = "eco2mix-workflow"
  description = "bronze -> silver -> gold"
}

resource "aws_glue_trigger" "start_job_1" {
  name              = "start-job-1"
  type              = "SCHEDULED"
  schedule          = "cron(30 6 * * ? *)"
  workflow_name     = aws_glue_workflow.eco2mix_workflow.name
  start_on_creation = true

  actions {
    job_name = aws_glue_job.etl_job_1.name
  }
}

resource "aws_glue_trigger" "start_job_2" {
  name              = "start-job-2"
  type              = "CONDITIONAL"
  workflow_name     = aws_glue_workflow.eco2mix_workflow.name
  start_on_creation = true

  predicate {
    conditions {
      job_name = aws_glue_job.etl_job_1.name
      state    = "SUCCEEDED"
    }
  }

  actions {
    job_name = aws_glue_job.etl_job_2.name
  }
}

#############################################################################
# Open-Meteo 

resource "aws_glue_catalog_table" "silver_openmeteo" {
  name          = "silver_openmeteo"
  database_name = aws_glue_catalog_database.CatalogDatabaseGlue.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"               = "parquet"
    "projection.enabled"           = "true"
    "projection.event_date.type"   = "date"
    "projection.event_date.format" = "yyyy-MM-dd"
    "projection.event_date.range"  = "2026-01-01,NOW+7DAYS" # prévisions : jusqu'à 7 jours dans le futur
    "storage.location.template"    = "s3://${aws_s3_bucket.Silver_bucket.id}/silver/open-meteo/forecast/event_date=$${event_date}/"
  }

  partition_keys {
    name = "event_date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.Silver_bucket.id}/silver/open-meteo/forecast/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "event_timestamp"
      type = "timestamp"
    }
    columns {
      name = "location"
      type = "string"
    }
    columns {
      name = "temperature_2m"
      type = "double"
    }
    columns {
      name = "wind_speed_100m"
      type = "double"
    }
    columns {
      name = "shortwave_radiation"
      type = "double"
    }
    columns {
      name = "dataset"
      type = "string"
    }
    columns {
      name = "source"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "gold_openmeteo" {
  name          = "gold_openmeteo"
  database_name = aws_glue_catalog_database.CatalogDatabaseGlue.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"               = "parquet"
    "projection.enabled"           = "true"
    "projection.event_date.type"   = "date"
    "projection.event_date.format" = "yyyy-MM-dd"
    "projection.event_date.range"  = "2026-01-01,NOW+7DAYS"
    "storage.location.template"    = "s3://${aws_s3_bucket.Gold_bucket.id}/gold/weather/forecast/event_date=$${event_date}/"
  }

  partition_keys {
    name = "event_date"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.Gold_bucket.id}/gold/weather/forecast/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }
    columns {
      name = "event_timestamp"
      type = "timestamp"
    }
    columns {
      name = "location"
      type = "string"
    }
    columns {
      name = "temperature_2m"
      type = "double"
    }
    columns {
      name = "precipitation"
      type = "double"
    }
    columns {
      name = "cloud_cover"
      type = "double"
    }
    columns {
      name = "wind_speed_100m"
      type = "double"
    }
    columns {
      name = "solar_radiation"
      type = "double"
    }
  }
}

resource "aws_glue_job" "etl_job_1_openmeteo" {
  name                   = "Job-Bronze-to-Silver-OpenMeteo"
  description            = "The job that transform bronze Open-Meteo data to silver"
  role_arn               = aws_iam_role.glue_job_role_1.arn
  glue_version           = "5.0"
  max_retries            = 0
  timeout                = 10
  number_of_workers      = 2
  worker_type            = "G.1X"
  execution_class        = "STANDARD"
  security_configuration = aws_glue_security_configuration.glue_logs_encryption.name

  command {
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/jobs/ETL-jobs1.py"
    name            = "glueetl"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--continuous-log-logGroup"          = "/aws-glue/jobs/OpenMeteoJobs1"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${aws_s3_bucket.glue_scripts.id}/glue-temp/"
    "--SOURCE"                           = "openmeteo"
    "--DATASET"                          = "forecast"
    "--BRONZE_PATH"                      = "s3://${aws_s3_bucket.Bronze_bucket.id}/open-meteo/forecast/"
    "--SILVER_PATH"                      = "s3://${aws_s3_bucket.Silver_bucket.id}/silver/open-meteo/forecast/"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    "ManagedBy" = "AWS"
  }
}

resource "aws_glue_job" "etl_job_2_openmeteo" {
  name                   = "Job-Silver-to-Gold-OpenMeteo"
  description            = "The job that transform silver Open-Meteo data to gold"
  role_arn               = aws_iam_role.glue_job_role_2.arn
  glue_version           = "5.0"
  max_retries            = 0
  timeout                = 10
  number_of_workers      = 2
  worker_type            = "G.1X"
  execution_class        = "STANDARD"
  security_configuration = aws_glue_security_configuration.glue_logs_encryption.name

  command {
    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/jobs/ETL-jobs2.py"
    name            = "glueetl"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--continuous-log-logGroup"          = "/aws-glue/jobs/OpenMeteoJobs2"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${aws_s3_bucket.glue_scripts.id}/glue-temp/"
    "--SOURCE"                           = "openmeteo"
    "--DATASET"                          = "forecast"
    "--SILVER_PATH"                      = "s3://${aws_s3_bucket.Silver_bucket.id}/silver/open-meteo/forecast/"
    "--GOLD_PATH"                        = "s3://${aws_s3_bucket.Gold_bucket.id}/gold"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    "ManagedBy" = "AWS"
  }
}

####################
# Workflow Open-Meteo 

resource "aws_glue_workflow" "openmeteo_workflow" {
  name        = "openmeteo-workflow"
  description = "bronze -> silver -> gold"
}

resource "aws_glue_trigger" "start_job_1_openmeteo" {
  name              = "start-job-1-openmeteo"
  type              = "SCHEDULED"
  schedule          = "cron(35 6 * * ? *)"
  workflow_name     = aws_glue_workflow.openmeteo_workflow.name
  start_on_creation = true

  actions {
    job_name = aws_glue_job.etl_job_1_openmeteo.name
  }
}

resource "aws_glue_trigger" "start_job_2_openmeteo" {
  name              = "start-job-2-openmeteo"
  type              = "CONDITIONAL"
  workflow_name     = aws_glue_workflow.openmeteo_workflow.name
  start_on_creation = true

  predicate {
    conditions {
      job_name = aws_glue_job.etl_job_1_openmeteo.name
      state    = "SUCCEEDED"
    }
  }

  actions {
    job_name = aws_glue_job.etl_job_2_openmeteo.name
  }
}
