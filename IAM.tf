data "aws_iam_policy_document" "assume_role_lambda" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

#############################################################################
# Role des 2 Lambdas d'ingestion 

resource "aws_iam_role" "Lambda_ingestion_role" {
  name               = "lambda_ingestion_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_lambda.json
}

data "aws_iam_policy_document" "Lambda_ingestion_policy" {
  statement {
    sid     = "WriteBronze"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.Bronze_bucket.arn}/rte/eco2mix/*",
      "${aws_s3_bucket.Bronze_bucket.arn}/open-meteo/forecast/*",
    ]
  }

  statement {
    sid       = "EncryptWithKeyBronze"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey"]
    resources = [aws_kms_key.key_bronze.arn]
  }

  statement {
    sid     = "Logs"
    effect  = "Allow"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/eCO2mix-ingestion-lambda:*",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/openmeteo-ingestion-lambda:*",
    ]
  }
}

resource "aws_iam_policy" "Lambda_ingestion_policy" {
  name   = "lambda_ingestion_policy"
  policy = data.aws_iam_policy_document.Lambda_ingestion_policy.json
}

resource "aws_iam_role_policy_attachment" "Lambda_ingestion_attachment" {
  role       = aws_iam_role.Lambda_ingestion_role.name
  policy_arn = aws_iam_policy.Lambda_ingestion_policy.arn
}

#############################################################################
# Role de la Lambda COPY : lancer le SQL dans Redshift
# (c'est Redshift qui lit le gold avec son propre rôle, voir Redshift.tf)

resource "aws_iam_role" "Lambda_copy_role" {
  name               = "lambda_copy_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_lambda.json
}

data "aws_iam_policy_document" "Lambda_copy_policy" {
  statement {
    sid       = "RunSQL"
    effect    = "Allow"
    actions   = ["redshift-data:BatchExecuteStatement"]
    resources = [aws_redshift_cluster.Tr_cluster.arn]
  }

  statement {
    sid       = "ReadSQLStatus"
    effect    = "Allow"
    actions   = ["redshift-data:DescribeStatement"]
    resources = ["*"] # cette action n'accepte pas d'ARN
  }

  statement {
    sid       = "ReadRedshiftPassword"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_redshift_cluster.Tr_cluster.master_password_secret_arn]
  }

  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/copy-gold-redshift-lambda:*"]
  }
}

resource "aws_iam_policy" "Lambda_copy_policy" {
  name   = "lambda_copy_policy"
  policy = data.aws_iam_policy_document.Lambda_copy_policy.json
}

resource "aws_iam_role_policy_attachment" "Lambda_copy_attachment" {
  role       = aws_iam_role.Lambda_copy_role.name
  policy_arn = aws_iam_policy.Lambda_copy_policy.arn
}

#############################################################################
# IAM role for Glue jobs

resource "aws_iam_role" "glue_job_role_1" {
  name = "glue-job-role-1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}


resource "aws_iam_role" "glue_job_role_2" {
  name = "glue-job-role-2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

#######
# Job 1 : lit le bronze, écrit le silver

data "aws_iam_policy_document" "glue_job_1_policy" {
  statement {
    sid       = "ReadScriptAndTemp"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.glue_scripts.arn}/*"]
  }

  statement {
    sid     = "ListBuckets"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.glue_scripts.arn,
      aws_s3_bucket.Bronze_bucket.arn,
      aws_s3_bucket.Silver_bucket.arn,
    ]
  }

  statement {
    sid     = "ReadBronze"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.Bronze_bucket.arn}/rte/eco2mix/*",
      "${aws_s3_bucket.Bronze_bucket.arn}/open-meteo/forecast/*",
    ]
  }

  statement {
    sid       = "WriteSilver"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.Silver_bucket.arn}/silver/*"]
  }

  statement {
    sid       = "KeyBronzeRead"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.key_bronze.arn]
  }

  statement {
    sid       = "KeySilverWrite"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.key_silver.arn]
  }

  statement {
    sid       = "GlueLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:AssociateKmsKey"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"]
  }

  statement {
    sid       = "GlueMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"] # cette action n'accepte pas d'ARN, on limite au namespace Glue
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Glue"]
    }
  }
}

resource "aws_iam_policy" "glue_job_1_policy" {
  name   = "glue-job-1-policy"
  policy = data.aws_iam_policy_document.glue_job_1_policy.json
}

resource "aws_iam_role_policy_attachment" "glue_job_1_attachment" {
  role       = aws_iam_role.glue_job_role_1.name
  policy_arn = aws_iam_policy.glue_job_1_policy.arn
}

#######
# Job 2 : lit le silver, écrit le gold

data "aws_iam_policy_document" "glue_job_2_policy" {
  statement {
    sid       = "ReadScriptAndTemp"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.glue_scripts.arn}/*"]
  }

  statement {
    sid     = "ListBuckets"
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.glue_scripts.arn,
      aws_s3_bucket.Silver_bucket.arn,
      aws_s3_bucket.Gold_bucket.arn,
    ]
  }

  statement {
    sid       = "ReadSilver"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.Silver_bucket.arn}/silver/*"]
  }

  statement {
    sid       = "WriteGold"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.Gold_bucket.arn}/gold/*"]
  }

  statement {
    sid       = "KeySilverRead"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.key_silver.arn]
  }

  statement {
    sid       = "KeyGoldWrite"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.key_gold.arn]
  }

  statement {
    sid       = "GlueLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:AssociateKmsKey"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"]
  }

  statement {
    sid       = "GlueMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"] # cette action n'accepte pas d'ARN, on limite au namespace Glue
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Glue"]
    }
  }
}

resource "aws_iam_policy" "glue_job_2_policy" {
  name   = "glue-job-2-policy"
  policy = data.aws_iam_policy_document.glue_job_2_policy.json
}

resource "aws_iam_role_policy_attachment" "glue_job_2_attachment" {
  role       = aws_iam_role.glue_job_role_2.name
  policy_arn = aws_iam_policy.glue_job_2_policy.arn
}
