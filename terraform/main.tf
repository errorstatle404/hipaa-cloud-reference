data "aws_caller_identity" "current" {}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  key_admin_arns   = length(var.key_admin_arns) > 0 ? var.key_admin_arns : [data.aws_caller_identity.current.arn]
  phi_bucket_name  = "${var.name_prefix}-phi-${local.account_id}"
  logs_bucket_name = "${var.name_prefix}-logs-${local.account_id}"
  trail_name       = "${var.name_prefix}-trail"
}

module "network" {
  source = "./modules/network"

  name_prefix         = var.name_prefix
  region              = var.region
  account_id          = local.account_id
  vpc_cidr            = var.vpc_cidr
  flow_log_bucket_arn = module.logging.logs_bucket_arn
}

module "logging" {
  source = "./modules/logging"

  name_prefix        = var.name_prefix
  region             = var.region
  account_id         = local.account_id
  key_admin_arns     = local.key_admin_arns
  logs_bucket_name   = local.logs_bucket_name
  trail_name         = local.trail_name
  phi_bucket_name    = local.phi_bucket_name
  log_retention_days = var.log_retention_days
  log_archive_days   = var.log_archive_days
  force_destroy      = var.lab_force_destroy
  enable_config      = var.enable_config
}

module "identity" {
  source = "./modules/identity"

  name_prefix            = var.name_prefix
  region                 = var.region
  account_id             = local.account_id
  phi_bucket_name        = local.phi_bucket_name
  data_key_arn           = module.storage.data_key_arn
  ingest_principal_arns  = local.key_admin_arns
  require_mfa_for_ingest = var.require_mfa_for_ingest
}

module "storage" {
  source = "./modules/storage"

  name_prefix      = var.name_prefix
  region           = var.region
  account_id       = local.account_id
  key_admin_arns   = local.key_admin_arns
  phi_bucket_name  = local.phi_bucket_name
  reader_role_arns = [module.identity.app_role_arn]
  writer_role_arns = [module.identity.ingest_role_arn]
  s3_endpoint_id   = module.network.s3_endpoint_id
  force_destroy    = var.lab_force_destroy
}

module "app" {
  source = "./modules/app"

  name_prefix        = var.name_prefix
  role_arn           = module.identity.app_role_arn
  subnet_ids         = module.network.app_subnet_ids
  security_group_ids = [module.network.app_security_group_id]
  phi_bucket_name    = module.storage.phi_bucket_name
  logs_key_arn       = module.logging.logs_key_arn
  log_retention_days = var.log_retention_days
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix        = var.name_prefix
  region             = var.region
  account_id         = local.account_id
  trail_log_group    = module.logging.trail_log_group_name
  logs_key_arn       = module.logging.logs_key_arn
  phi_bucket_name    = local.phi_bucket_name
  alert_email        = var.alert_email
  enable_guardduty   = var.enable_guardduty
  enable_securityhub = var.enable_securityhub
}
