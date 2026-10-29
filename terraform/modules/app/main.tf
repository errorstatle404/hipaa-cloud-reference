locals {
  function_name = "${var.name_prefix}-phi-reader"
}

data "archive_file" "handler" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_key_arn
}

# The application tier: reads synthetic FHIR records from inside the VPC and
# returns only aggregate counts, never record contents (minimum necessary).
resource "aws_lambda_function" "reader" {
  #checkov:skip=CKV_AWS_115:New accounts have a 10-execution concurrency quota and AWS rejects reservations that leave fewer than 10 unreserved (ADR-008).
  #checkov:skip=CKV_AWS_116:Invoked synchronously only; a DLQ applies to async invocations.
  #checkov:skip=CKV_AWS_272:Code signing (AWS Signer) is listed as a production addition (ADR-008).
  #checkov:skip=CKV_AWS_173:Environment holds only the bucket name and prefix, no secrets.
  function_name    = local.function_name
  description      = "Reads synthetic PHI through the S3 VPC endpoint; returns aggregates only"
  role             = var.role_arn
  runtime          = "python3.13"
  handler          = "handler.handler"
  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256
  timeout          = 30
  memory_size      = 256

  tracing_config {
    mode = "Active"
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  environment {
    variables = {
      PHI_BUCKET = var.phi_bucket_name
      PHI_PREFIX = "fhir/"
    }
  }

  depends_on = [aws_cloudwatch_log_group.fn]
}
