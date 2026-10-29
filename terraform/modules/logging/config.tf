# AWS Config: records resource configuration over time and evaluates managed
# rules chosen for their mapping to the HIPAA Security Rule technical
# safeguards (see docs/control-matrix.md).

data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0

  name               = "${var.name_prefix}-config"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
}

resource "aws_iam_role_policy_attachment" "config" {
  count = var.enable_config ? 1 : 0

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_delivery" {
  count = var.enable_config ? 1 : 0

  name = "deliver-to-log-bucket"
  role = aws_iam_role.config[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.logs.arn}/config/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource = aws_s3_bucket.logs.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.logs.arn
      },
    ]
  })
}

resource "aws_config_configuration_recorder" "this" {
  count = var.enable_config ? 1 : 0

  name     = "${var.name_prefix}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  count = var.enable_config ? 1 : 0

  name           = "${var.name_prefix}-delivery"
  s3_bucket_name = aws_s3_bucket.logs.id
  s3_key_prefix  = "config"
  s3_kms_key_arn = aws_kms_key.logs.arn

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_iam_role_policy.config_delivery,
    aws_s3_bucket_policy.logs,
  ]
}

resource "aws_config_configuration_recorder_status" "this" {
  count = var.enable_config ? 1 : 0

  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

locals {
  # rule identifier => HIPAA 164.312 reference (also in docs/control-matrix.md)
  config_rules = var.enable_config ? {
    "CLOUD_TRAIL_ENABLED"                            = "164.312(b)"
    "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"        = "164.312(c)(1)"
    "CLOUD_TRAIL_ENCRYPTION_ENABLED"                 = "164.312(a)(2)(iv)"
    "CMK_BACKING_KEY_ROTATION_ENABLED"               = "164.312(a)(2)(iv)"
    "CLOUDWATCH_LOG_GROUP_ENCRYPTED"                 = "164.312(a)(2)(iv)"
    "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"       = "164.312(a)(2)(iv)"
    "S3_BUCKET_SSL_REQUESTS_ONLY"                    = "164.312(e)(1)"
    "S3_BUCKET_PUBLIC_READ_PROHIBITED"               = "164.312(a)(1)"
    "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"              = "164.312(a)(1)"
    "S3_ACCOUNT_LEVEL_PUBLIC_ACCESS_BLOCKS_PERIODIC" = "164.312(a)(1)"
    "S3_BUCKET_VERSIONING_ENABLED"                   = "164.312(c)(1)"
    "IAM_ROOT_ACCESS_KEY_CHECK"                      = "164.312(a)(1)"
    "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"     = "164.312(a)(1)"
    "ROOT_ACCOUNT_MFA_ENABLED"                       = "164.312(d)"
    "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"             = "164.312(d)"
    "VPC_FLOW_LOGS_ENABLED"                          = "164.312(b)"
    "VPC_DEFAULT_SECURITY_GROUP_CLOSED"              = "164.312(e)(1)"
    "LAMBDA_INSIDE_VPC"                              = "164.312(e)(1)"
  } : {}
}

resource "aws_config_config_rule" "hipaa" {
  for_each = local.config_rules

  name        = "${var.name_prefix}-${lower(replace(each.key, "_", "-"))}"
  description = "HIPAA ${each.value}"

  source {
    owner             = "AWS"
    source_identifier = each.key
  }

  depends_on = [aws_config_configuration_recorder_status.this]
}
