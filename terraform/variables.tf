variable "region" {
  description = "AWS region for the build."
  type        = string
  default     = "us-east-2"
}

variable "owner" {
  description = "Owner tag applied to every resource."
  type        = string
  default     = "evy"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "hipaa-ref"
}

variable "key_admin_arns" {
  description = "IAM principals allowed to administer (but not use) the KMS keys. Empty = the identity running Terraform."
  type        = list(string)
  default     = []
}

variable "alert_email" {
  description = "Email address subscribed to security alarms. Empty = no subscription."
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the workload VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "log_retention_days" {
  description = "Days to keep CloudWatch log groups."
  type        = number
  default     = 365
}

variable "log_archive_days" {
  description = "Days to keep audit logs in S3. 2190 = 6 years, mirroring HIPAA's documentation retention period."
  type        = number
  default     = 2190
}

variable "lab_force_destroy" {
  description = "Allow terraform destroy to delete non-empty buckets. True for the lab only (see ADR-010)."
  type        = bool
  default     = true
}

variable "require_mfa_for_ingest" {
  description = "Require MFA when assuming the data-ingest role."
  type        = bool
  default     = false
}

variable "enable_config" {
  description = "Turn on the AWS Config recorder and HIPAA-mapped managed rules."
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Turn on GuardDuty (bounded demo window; bills after the trial)."
  type        = bool
  default     = false
}

variable "enable_securityhub" {
  description = "Turn on Security Hub with the CIS AWS Foundations standard (bounded demo window)."
  type        = bool
  default     = false
}
