output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "ingest_role_arn" {
  value = aws_iam_role.ingest.arn
}

output "boundary_policy_arn" {
  value = aws_iam_policy.boundary.arn
}
