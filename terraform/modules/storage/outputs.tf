output "phi_bucket_name" {
  value = aws_s3_bucket.phi.id
}

output "phi_bucket_arn" {
  value = aws_s3_bucket.phi.arn
}

output "data_key_arn" {
  value = aws_kms_key.data.arn
}
