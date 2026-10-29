variable "name_prefix" { type = string }
variable "role_arn" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "phi_bucket_name" { type = string }
variable "logs_key_arn" { type = string }
variable "log_retention_days" { type = number }
