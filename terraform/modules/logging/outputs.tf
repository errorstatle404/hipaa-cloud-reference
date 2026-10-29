output "logs_key_arn" {
  value = aws_kms_key.logs.arn
}

output "logs_bucket_name" {
  value = aws_s3_bucket.logs.id
}

# Consumers (flow logs) must wait for the bucket policy that lets them write.
output "logs_bucket_arn" {
  value      = aws_s3_bucket.logs.arn
  depends_on = [aws_s3_bucket_policy.logs]
}

output "trail_name" {
  value = aws_cloudtrail.this.name
}

output "trail_log_group_name" {
  value = aws_cloudwatch_log_group.trail.name
}
