output "vpc_id" {
  value = aws_vpc.this.id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "s3_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}
