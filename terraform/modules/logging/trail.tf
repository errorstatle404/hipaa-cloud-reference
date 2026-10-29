resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${var.trail_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
}

data "aws_iam_policy_document" "trail_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "trail_to_cwl" {
  name               = "${var.name_prefix}-cloudtrail-to-cwl"
  assume_role_policy = data.aws_iam_policy_document.trail_assume.json
}

resource "aws_iam_role_policy" "trail_to_cwl" {
  name = "write-trail-log-group"
  role = aws_iam_role.trail_to_cwl.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.trail.arn}:*"
    }]
  })
}

# Multi-region trail with log file validation (tamper evidence), KMS
# encryption, and S3 data events on the PHI bucket so every read and write of
# a patient record is attributable to an identity (HIPAA 164.312(b)).
resource "aws_cloudtrail" "this" {
  #checkov:skip=CKV_AWS_252:Alerting runs on CloudWatch metric filters; per-delivery SNS notifications would only add noise.
  name                          = var.trail_name
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.logs.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.trail_to_cwl.arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${var.phi_bucket_name}/"]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_iam_role_policy.trail_to_cwl,
  ]
}
