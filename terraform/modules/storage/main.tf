locals {
  key_admin_actions = [
    "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
    "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
    "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion", "kms:RotateKeyOnDemand",
  ]
}

# Customer-managed key for PHI. The key policy has no "delegate to IAM"
# statement for the account root, so an IAM admin policy alone cannot grant
# decrypt: only the workload roles listed here can use the key, and only
# through S3 (ADR-005).
data "aws_iam_policy_document" "data_key" {
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
    sid       = "ReadersDecryptViaS3"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = var.reader_role_arns
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "WritersEncryptViaS3"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = var.writer_role_arns
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "data" {
  description             = "${var.name_prefix} PHI data (synthetic)"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.data_key.json
}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.name_prefix}-phi"
  target_key_id = aws_kms_key.data.key_id
}

resource "aws_s3_bucket" "phi" {
  #checkov:skip=CKV_AWS_18:Object-level access is logged by CloudTrail data events; S3 server access logs cannot target an SSE-KMS bucket (ADR-007).
  #checkov:skip=CKV_AWS_144:Cross-region replication is a production addition; out of scope for the lab budget (ADR-010).
  #checkov:skip=CKV2_AWS_62:No event-driven consumers; alerting runs on CloudTrail metric filters instead.
  bucket        = var.phi_bucket_name
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_ownership_controls" "phi" {
  bucket = aws_s3_bucket.phi.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "phi" {
  bucket                  = aws_s3_bucket.phi.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "phi" {
  bucket = aws_s3_bucket.phi.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "phi" {
  bucket = aws_s3_bucket.phi.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "phi" {
  bucket = aws_s3_bucket.phi.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "phi_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.phi.arn, "${aws_s3_bucket.phi.arn}/*"]

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
    sid       = "DenyOutdatedTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.phi.arn, "${aws_s3_bucket.phi.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }

  # Patient records can only be read from inside the VPC. Even the account
  # administrator gets AccessDenied from a laptop on the internet.
  statement {
    sid       = "DenyReadsOutsideVpcEndpoint"
    effect    = "Deny"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.phi.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [var.s3_endpoint_id]
    }
  }

  # Only the ingest role may add records.
  statement {
    sid       = "DenyWritesExceptIngestRole"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.phi.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = var.writer_role_arns
    }
  }

  # Every object must be encrypted with this bucket's key, never another one.
  statement {
    sid       = "DenyWrongEncryptionKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.phi.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.data.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "phi" {
  bucket = aws_s3_bucket.phi.id
  policy = data.aws_iam_policy_document.phi_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.phi]
}
