terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~>2.7"
    }

    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

data "aws_region" "current" {}


locals {
  kms_admin_actions = [
    "kms:Create*",
    "kms:Describe*",
    "kms:Enable*",
    "kms:List*",
    "kms:Put*",
    "kms:Update*",
    "kms:Revoke*",
    "kms:Disable*",
    "kms:Get*",
    "kms:Delete*",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion",
  ]
}

resource "random_id" "suffix" {
  byte_length = 8
}

#############################################################################
# Lambda ingestion eCO2mix

data "archive_file" "Lambda_ingestion_eCO2mix" {
  type        = "zip"
  source_file = "${path.module}/Lambda_ingestion_eco2mix.py"
  output_path = "${path.module}/Lambda_ingestion_eco2mix.zip"
}

resource "aws_lambda_function" "Lambda_ingestion_eCO2mix" {
  filename         = data.archive_file.Lambda_ingestion_eCO2mix.output_path
  function_name    = "eCO2mix-ingestion-lambda"
  role             = aws_iam_role.Lambda_ingestion_role.arn
  handler          = "Lambda_ingestion_eco2mix.lambda_handler"
  source_code_hash = data.archive_file.Lambda_ingestion_eCO2mix.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      BRONZE_BUCKET            = aws_s3_bucket.Bronze_bucket.id
      RTE_REALTIME_DATASET     = "eco2mix-national-tr"
      RTE_CONSOLIDATED_DATASET = "eco2mix-national-cons-def"
      RTE_REGIONAL_DATASET     = "eco2mix-regional-tr"
    }
  }
}

#######
#si pas de Step Function
resource "aws_cloudwatch_event_rule" "Lambda_ingestion_eco2mix" {
  name                = "Eventbridge-lambda-ingestion-eco2mix"
  description         = "execute lambda_ingestion eco2mix"
  schedule_expression = "cron(*/15 8-23 * * ? *)"
}

resource "aws_cloudwatch_event_target" "Lambda_ingestion_eco2mix" {
  rule  = aws_cloudwatch_event_rule.Lambda_ingestion_eco2mix.name
  arn   = aws_lambda_function.Lambda_ingestion_eCO2mix.arn
  input = jsonencode({ dataset = "national-realtime" })
}

resource "aws_lambda_permission" "allow_EventBridge_eco2mix" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.Lambda_ingestion_eCO2mix.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.Lambda_ingestion_eco2mix.arn
}

#############################################################################
# Lambda ingestion Open-Meteo

data "archive_file" "Lambda_ingestion_openmeteo" {
  type        = "zip"
  source_file = "${path.module}/Lambda_ingestion_openmeteo.py"
  output_path = "${path.module}/Lambda_ingestion_openmeteo.zip"
}

resource "aws_lambda_function" "Lambda_ingestion_openmeteo" {
  filename         = data.archive_file.Lambda_ingestion_openmeteo.output_path
  function_name    = "openmeteo-ingestion-lambda"
  role             = aws_iam_role.Lambda_ingestion_role.arn
  handler          = "Lambda_ingestion_openmeteo.lambda_handler"
  source_code_hash = data.archive_file.Lambda_ingestion_openmeteo.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      BRONZE_BUCKET = aws_s3_bucket.Bronze_bucket.id
    }
  }
}

#######
#si pas de Step Function
resource "aws_cloudwatch_event_rule" "Lambda_ingestion_openmeteo" {
  name                = "Eventbridge-lambda-ingestion-openmeteo"
  description         = "execute lambda_ingestion openmeteo"
  schedule_expression = "cron(*/15 8-23 * * ? *)"
}

resource "aws_cloudwatch_event_target" "Lambda_ingestion_openmeteo" {
  rule = aws_cloudwatch_event_rule.Lambda_ingestion_openmeteo.name
  arn  = aws_lambda_function.Lambda_ingestion_openmeteo.arn
}

resource "aws_lambda_permission" "allow_EventBridge_openmeteo" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.Lambda_ingestion_openmeteo.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.Lambda_ingestion_openmeteo.arn
}

#############################################################################
# Lambda COPY gold -> Redshift 

data "archive_file" "Lambda_copy_s3gold_redshift" {
  type        = "zip"
  source_file = "${path.module}/Lambda_copy_s3gold_redshift.py"
  output_path = "${path.module}/Lambda_copy_s3gold_redshift.zip"
}

resource "aws_lambda_function" "Lambda_copy_s3gold_redshift" {
  filename         = data.archive_file.Lambda_copy_s3gold_redshift.output_path
  function_name    = "copy-gold-redshift-lambda"
  role             = aws_iam_role.Lambda_copy_role.arn
  handler          = "Lambda_copy_s3gold_redshift.lambda_handler"
  source_code_hash = data.archive_file.Lambda_copy_s3gold_redshift.output_base64sha256
  runtime          = "python3.12"
  timeout          = 300

  environment {
    variables = {
      CLUSTER_ID    = aws_redshift_cluster.Tr_cluster.cluster_identifier
      DATABASE      = aws_redshift_cluster.Tr_cluster.database_name
      SECRET_ARN    = aws_redshift_cluster.Tr_cluster.master_password_secret_arn
      COPY_ROLE_ARN = aws_iam_role.redshift_s3_role.arn
      GOLD_BUCKET   = aws_s3_bucket.Gold_bucket.id
      JOB_ECO2MIX   = aws_glue_job.etl_job_2.name
      JOB_OPENMETEO = aws_glue_job.etl_job_2_openmeteo.name
    }
  }
}

#######
#si pas de Step Function
resource "aws_cloudwatch_event_rule" "Job2_succeeded" {
  name        = "Eventbridge-job2-succeeded"
  description = "execute lambda copy quand un job 2 a reussi"
  event_pattern = jsonencode({
    source        = ["aws.glue"]
    "detail-type" = ["Glue Job State Change"]
    detail = {
      jobName = [aws_glue_job.etl_job_2.name, aws_glue_job.etl_job_2_openmeteo.name]
      state   = ["SUCCEEDED"]
    }
  })
}

resource "aws_cloudwatch_event_target" "Job2_succeeded" {
  rule = aws_cloudwatch_event_rule.Job2_succeeded.name
  arn  = aws_lambda_function.Lambda_copy_s3gold_redshift.arn
}

resource "aws_lambda_permission" "allow_EventBridge_copy" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.Lambda_copy_s3gold_redshift.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.Job2_succeeded.arn
}
