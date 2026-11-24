data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "redshift_kms_policy" {

  statement {
    sid    = "EnableRootPermissions"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRedshiftKMS"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }
    actions = [
      "kms:DescribeKey",
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:ReEncrypt*",
      "kms:RetireGrant"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "Redshift_kms" {
  description             = "The key for redshift usage"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.redshift_kms_policy.json
}


resource "aws_redshift_cluster" "Tr_cluster" {
  cluster_identifier           = "tf-redshift-cluster"
  database_name                = "energiedatabase" # minuscules obligatoires
  master_username              = "userroot"
  node_type                    = "ra3.xlplus"
  cluster_type                 = "single-node"
  encrypted                    = "true"
  vpc_security_group_ids       = [aws_security_group.allow_com_redshift_bi.id]
  kms_key_id                   = aws_kms_key.Redshift_kms.id
  iam_roles                    = [aws_iam_role.redshift_s3_role.arn]
  enhanced_vpc_routing         = "true"
  publicly_accessible          = "false"
  cluster_subnet_group_name    = aws_redshift_subnet_group.redshift_sb.name
  cluster_parameter_group_name = aws_redshift_parameter_group.redshift_pg.name

  manage_master_password = true
  skip_final_snapshot    = true # sinon le terraform destroy demande un nom de snapshot
}

data "aws_iam_policy_document" "redshift_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "redshift.amazonaws.com"
      ]
    }

    actions = ["sts:AssumeRole"]
  }
}


resource "aws_iam_role" "redshift_s3_role" {
  name               = "redshift-s3-access"
  assume_role_policy = data.aws_iam_policy_document.redshift_assume_role.json
}

data "aws_iam_policy_document" "redshift_s3_policy" {

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.Gold_bucket.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.Gold_bucket.arn}/gold/*"]
  }

  statement {
    sid    = "DecryptS3GoldObjects"
    effect = "Allow"
    actions = ["kms:Decrypt",
    "kms:DescribeKey"]
    resources = [aws_kms_key.key_gold.arn]
  }
}

resource "aws_iam_policy" "redshift_s3_policy" {
  name   = "redshift-s3-read"
  policy = data.aws_iam_policy_document.redshift_s3_policy.json
}

resource "aws_iam_role_policy_attachment" "redshift_s3_attachment" {
  role       = aws_iam_role.redshift_s3_role.name
  policy_arn = aws_iam_policy.redshift_s3_policy.arn
}


####################################
#Section vpc 

resource "aws_vpc" "redshift_dedicated" {
  cidr_block = "10.1.0.0/16"
}

resource "aws_subnet" "subnet_private1" {
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "eu-west-1a"
  vpc_id                  = aws_vpc.redshift_dedicated.id
  map_public_ip_on_launch = "false"

  tags = {
    Name = "Subnet-private-redshift-1"
  }
}

resource "aws_subnet" "subnet_private2" {
  cidr_block              = "10.1.2.0/24"
  availability_zone       = "eu-west-1b"
  vpc_id                  = aws_vpc.redshift_dedicated.id
  map_public_ip_on_launch = "false"

  tags = {
    Name = "Subnet-private-redshift-2"
  }
}

resource "aws_route_table" "rt_private" {
  vpc_id = aws_vpc.redshift_dedicated.id

  tags = {
    Name        = "redshift-private-rt"
    Environment = "Production"
  }
}

resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.subnet_private1.id
  route_table_id = aws_route_table.rt_private.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.subnet_private2.id
  route_table_id = aws_route_table.rt_private.id
}


resource "aws_network_acl" "nacl_subnet_1n2" {
  vpc_id     = aws_vpc.redshift_dedicated.id
  subnet_ids = [aws_subnet.subnet_private1.id, aws_subnet.subnet_private2.id]

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "10.50.0.0/24"
    from_port  = 5439
    to_port    = 5439
  }

  egress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "10.50.0.0/24"
    from_port  = 1025
    to_port    = 65535
  }

  egress {
    protocol   = "tcp"
    rule_no    = 130
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "nacl_subnet1n2_redshift"
  }
}


resource "aws_security_group" "allow_com_redshift_bi" {
  name        = "allow_com_redshift_bi"
  description = "Allow Redshift to communicate with BI"
  vpc_id      = aws_vpc.redshift_dedicated.id

  tags = {
    Name = "allow_com_redshift_bi"
  }
}

resource "aws_security_group_rule" "ingress_redshift" {
  type              = "ingress"
  from_port         = 5439
  to_port           = 5439
  protocol          = "tcp"
  cidr_blocks       = ["10.50.0.0/24"]
  security_group_id = aws_security_group.allow_com_redshift_bi.id
}

resource "aws_security_group_rule" "egress_redshift" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.allow_com_redshift_bi.id
}



resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.redshift_dedicated.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.rt_private.id]
}


#############################################

resource "aws_redshift_subnet_group" "redshift_sb" {
  name       = "redshift-sb"
  subnet_ids = [aws_subnet.subnet_private1.id, aws_subnet.subnet_private2.id]

  tags = {
    environment = "Production"
  }
}

resource "aws_redshift_parameter_group" "redshift_pg" {
  name   = "parameter-group-redshift"
  family = "redshift-1.0"

  parameter {
    name  = "require_ssl"
    value = "true"
  }

  parameter {
    name  = "query_group"
    value = "reporting"
  }

  parameter {
    name  = "enable_user_activity_logging"
    value = "true"
  }
}



resource "aws_redshift_logging" "rd_logging" {
  cluster_identifier   = aws_redshift_cluster.Tr_cluster.id
  log_destination_type = "cloudwatch"
  log_exports          = ["connectionlog", "userlog", "useractivitylog"]
}



####################
#IAM role for scheduled action

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["scheduler.redshift.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "scheduleA_role" {
  name               = "redshift_scheduled_action"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "permissions_role" {
  statement {
    effect = "Allow"
    actions = [
      "redshift:PauseCluster",
      "redshift:ResumeCluster",
      "redshift:ResizeCluster",
    ]
    resources = [aws_redshift_cluster.Tr_cluster.arn]
  }
}

resource "aws_iam_policy" "scheduleA_policy" {
  name   = "redshift_scheduled_action"
  policy = data.aws_iam_policy_document.permissions_role.json
}

resource "aws_iam_role_policy_attachment" "scheduleA_attachement" {
  policy_arn = aws_iam_policy.scheduleA_policy.arn
  role       = aws_iam_role.scheduleA_role.name
}

###################################



resource "aws_redshift_scheduled_action" "schedule_action_redshift" {
  name        = "pause-trading-redshift"
  description = "Pause Redshift at 23:00 UTC"
  schedule    = "cron(00 23 * * ? *)"
  iam_role    = aws_iam_role.scheduleA_role.arn

  target_action {
    pause_cluster {
      cluster_identifier = aws_redshift_cluster.Tr_cluster.cluster_identifier
    }
  }
}

resource "aws_redshift_scheduled_action" "resume_redshift" {

  name        = "resume-trading-redshift"
  description = "Resume Redshift at 06:00 UTC"
  schedule    = "cron(0 6 * * ? *)"
  iam_role    = aws_iam_role.scheduleA_role.arn

  target_action {
    resume_cluster {
      cluster_identifier = aws_redshift_cluster.Tr_cluster.cluster_identifier
    }
  }
}





