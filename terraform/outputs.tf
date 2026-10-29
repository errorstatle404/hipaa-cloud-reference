output "account_id" {
  value = local.account_id
}

output "region" {
  value = var.region
}

output "phi_bucket" {
  value = module.storage.phi_bucket_name
}

output "data_key_arn" {
  value = module.storage.data_key_arn
}

output "logs_bucket" {
  value = module.logging.logs_bucket_name
}

output "logs_key_arn" {
  value = module.logging.logs_key_arn
}

output "trail_name" {
  value = module.logging.trail_name
}

output "ingest_role_arn" {
  value = module.identity.ingest_role_arn
}

output "app_function_name" {
  value = module.app.function_name
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "s3_endpoint_id" {
  value = module.network.s3_endpoint_id
}

output "alerts_topic_arn" {
  value = module.monitoring.alerts_topic_arn
}
