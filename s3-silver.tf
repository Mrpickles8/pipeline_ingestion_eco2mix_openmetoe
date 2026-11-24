resource "aws_kms_key" "key_silver" {
  description             = "This key is for the Silver bucket"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.key_silver_policy.json
}

####################
# Key policy 

data "aws_iam_policy_document" "key_silver_policy" {
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
    sid       = "GlueJob1Write"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.glue_job_role_1.arn]
    }
  }

  statement {
    sid       = "GlueJob2Read"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.glue_job_role_2.arn]
    }
  }
}


resource "aws_s3_bucket" "Silver_bucket" {
  bucket = "silver-bucket-${random_id.suffix.hex}"

  tags = {
    Name = "My Silver bucket"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "silver_bucket_config" {
  bucket = aws_s3_bucket.Silver_bucket.bucket

  rule {
    id = "silvercycle"


    status = "Enabled"

    transition {
      days          = 40
      storage_class = "GLACIER_IR"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }

    expiration {
      days = 120
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "Silver_bucket_encryption" {
  bucket = aws_s3_bucket.Silver_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.key_silver.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "Silver_bucket" {
  bucket = aws_s3_bucket.Silver_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


####################
# Bucket policy 
data "aws_iam_policy_document" "Silver_bucket_policy" {
  statement {
    sid       = "DenyNoSSL"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.Silver_bucket.arn, "${aws_s3_bucket.Silver_bucket.arn}/*"]
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
    resources = ["${aws_s3_bucket.Silver_bucket.arn}/*"]
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
    resources = ["${aws_s3_bucket.Silver_bucket.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.key_silver.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "Silver_bucket" {
  bucket = aws_s3_bucket.Silver_bucket.id
  policy = data.aws_iam_policy_document.Silver_bucket_policy.json
}
