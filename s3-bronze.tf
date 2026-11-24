resource "aws_kms_key" "key_bronze" {
  description             = "This key is for the Bronze bucket"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.key_bronze_policy.json
}

####################
# Key policy 

data "aws_iam_policy_document" "key_bronze_policy" {
  statement {
    sid       = "KeyAdministration"
    effect    = "Allow"
    actions   = local.kms_admin_actions
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "LambdaIngestionWrite"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.Lambda_ingestion_role.arn]
    }
  }

  statement {
    sid       = "GlueJob1Read" # le job 1 lit le bronze
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.glue_job_role_1.arn]
    }
  }
}


resource "aws_s3_bucket" "Bronze_bucket" {
  bucket              = "bronze-bucket-${random_id.suffix.hex}"
  object_lock_enabled = true
  tags = {
    Name = "My Bronze bucket"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bronze_bucket_config" {
  bucket = aws_s3_bucket.Bronze_bucket.bucket

  rule {
    id = "bronzecycle"


    status = "Enabled"

    transition {
      days          = 60
      storage_class = "GLACIER"
    }

    expiration {
      days = 120
    }
  }
}



resource "aws_s3_bucket_server_side_encryption_configuration" "Bronze_bucket_encryption" {
  bucket = aws_s3_bucket.Bronze_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.key_bronze.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "Bronze_bucket" {
  bucket = aws_s3_bucket.Bronze_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_versioning" "versioning_Bronze_bucket" {
  bucket = aws_s3_bucket.Bronze_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_s3_bucket_object_lock_configuration" "Bronze_bucket_object_lock" {
  bucket = aws_s3_bucket.Bronze_bucket.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 5
    }
  }

  depends_on = [aws_s3_bucket_versioning.versioning_Bronze_bucket]
}

####################
# Bucket policy 

data "aws_iam_policy_document" "Bronze_bucket_policy" {
  statement {
    sid       = "DenyNoSSL"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.Bronze_bucket.arn, "${aws_s3_bucket.Bronze_bucket.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyNotKMS"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.Bronze_bucket.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid       = "DenyWrongKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.Bronze_bucket.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.key_bronze.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "Bronze_bucket" {
  bucket = aws_s3_bucket.Bronze_bucket.id
  policy = data.aws_iam_policy_document.Bronze_bucket_policy.json
}
