locals {
  trail_arn = "arn:aws:cloudtrail:${var.region}:${var.account_id}:trail/${var.trail_name}"
}

# Customer-managed key for all audit data: CloudTrail, flow logs, Config,
# CloudWatch log groups and the alert topic. Administrators can manage the key
# but cannot use it to decrypt (ADR-005).
data "aws_iam_policy_document" "logs_key" {
  #checkov:skip=CKV_AWS_111:In a key policy, Resource "*" means this key only.
  #checkov:skip=CKV_AWS_356:Same reason: key policies always use Resource "*".
  statement {
    sid       = "KeyAdministration"
    effect    = "Allow"
    actions   = local.key_admin_actions
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = var.key_admin_arns
    }
  }

  statement {
    sid       = "CloudTrailEncrypt"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${var.account_id}:trail/*"]
    }
  }

  statement {
    sid       = "CloudTrailDescribe"
    effect    = "Allow"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "FlowLogsDelivery"
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }

  statement {
    sid       = "CloudWatchLogGroups"
    effect    = "Allow"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:*"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsToEncryptedTopic"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }

  dynamic "statement" {
    for_each = var.enable_config ? [1] : []
    content {
      sid       = "ConfigDelivery"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = [aws_iam_role.config[0].arn]
      }
    }
  }

  # Lets the key-rotation Config rule read this key. Metadata only, no key use.
  dynamic "statement" {
    for_each = var.enable_config ? [1] : []
    content {
      sid       = "ConfigEvaluateKey"
      effect    = "Allow"
      actions   = ["kms:DescribeKey", "kms:GetKeyRotationStatus"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = [aws_iam_role.config[0].arn]
      }
    }
  }
}

locals {
  key_admin_actions = [
    "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
    "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
    "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion", "kms:RotateKeyOnDemand",
  ]
}

resource "aws_kms_key" "logs" {
  description             = "${var.name_prefix} audit logs"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.logs_key.json
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name_prefix}-logs"
  target_key_id = aws_kms_key.logs.key_id
}
