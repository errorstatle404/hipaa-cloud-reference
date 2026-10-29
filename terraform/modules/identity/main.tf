locals {
  phi_bucket_arn = "arn:aws:s3:::${var.phi_bucket_name}"
}

# Permissions boundary: the ceiling for every workload role in this build.
# Even if someone later attaches AdministratorAccess to one of these roles,
# the role still cannot act outside this list (ADR-006).
data "aws_iam_policy_document" "boundary" {
  #checkov:skip=CKV_AWS_111:ENI and X-Ray actions do not support resource-level permissions; a boundary is a ceiling, not a grant.
  #checkov:skip=CKV_AWS_356:Same reason: these actions only accept "*" as the resource.
  statement {
    sid       = "PhiBucket"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:ListBucket"]
    resources = [local.phi_bucket_arn, "${local.phi_bucket_arn}/*"]
  }

  statement {
    sid       = "PhiKeyThroughS3"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["arn:aws:kms:${var.region}:${var.account_id}:key/*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "OwnLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/${var.name_prefix}-*"]
  }

  statement {
    sid = "LambdaVpcNetworking"
    actions = [
      "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses", "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Tracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }

  statement {
    sid       = "NeverIdentityOrKeyAdmin"
    effect    = "Deny"
    actions   = ["iam:*", "organizations:*", "sts:AssumeRole", "kms:Create*", "kms:Put*", "kms:Disable*", "kms:ScheduleKeyDeletion"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${var.name_prefix}-workload-boundary"
  description = "Permissions boundary for ${var.name_prefix} workload roles"
  policy      = data.aws_iam_policy_document.boundary.json
}

# ---------- App role: the PHI reader Lambda ----------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "app" {
  name                 = "${var.name_prefix}-app"
  description          = "PHI reader Lambda: read-only on the PHI bucket"
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume.json
  permissions_boundary = aws_iam_policy.boundary.arn
}

resource "aws_iam_role_policy_attachment" "app_vpc" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "app_xray" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "app" {
  name = "read-phi"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListPhi"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = local.phi_bucket_arn
      },
      {
        Sid      = "ReadPhi"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${local.phi_bucket_arn}/*"
      },
      {
        Sid      = "DecryptPhi"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.data_key_arn
      },
    ]
  })
}

# ---------- Ingest role: the only identity that can add records ----------

data "aws_iam_policy_document" "ingest_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.ingest_principal_arns
    }

    dynamic "condition" {
      for_each = var.require_mfa_for_ingest ? [1] : []
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
  }
}

resource "aws_iam_role" "ingest" {
  name                 = "${var.name_prefix}-ingest"
  description          = "Uploads synthetic records into the PHI bucket; cannot read them back"
  assume_role_policy   = data.aws_iam_policy_document.ingest_assume.json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "ingest" {
  name = "write-phi"
  role = aws_iam_role.ingest.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListPhi"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = local.phi_bucket_arn
      },
      {
        Sid      = "WritePhi"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${local.phi_bucket_arn}/*"
      },
      {
        Sid      = "EncryptPhi"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = var.data_key_arn
      },
    ]
  })
}

# ---------- Account baseline (CIS AWS Foundations) ----------

# Flags any resource shared outside the account (free).
resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "${var.name_prefix}-analyzer"
  type          = "ACCOUNT"
}

resource "aws_iam_account_password_policy" "cis" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 90
}

resource "aws_s3_account_public_access_block" "account" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "account" {
  enabled = true
}
