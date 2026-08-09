variable "vpc_id" {
  description = "Existing Butterfly Room VPC ID."
  type        = string
  default     = "vpc-05d7e03b48c391388"
}

variable "public_subnet_id" {
  description = "Existing public subnet for the staging EC2 instance."
  type        = string
  default     = "subnet-0c1b927d05f43c408"
}

variable "existing_alb_name" {
  description = "Existing production ALB shared with staging host rules."
  type        = string
  default     = "butterfly-room-alb"
}

variable "existing_rds_identifier" {
  description = "Existing RDS instance shared at the instance level only."
  type        = string
  default     = "corporate-prod"
}

variable "google_sheets_credentials_secret_name" {
  description = "Name of the existing staging Secrets Manager secret containing Google Sheets service account credentials. The secret value is not managed by Terraform."
  type        = string
  nullable    = false

  validation {
    condition     = trimspace(var.google_sheets_credentials_secret_name) != ""
    error_message = "google_sheets_credentials_secret_name must not be empty."
  }
}

variable "hosted_zone_name" {
  description = "Existing public Route 53 hosted zone."
  type        = string
  default     = "butterflyve.jp"
}

variable "staging_domain" {
  description = "Staging application hostname."
  type        = string
  default     = "staging.butterflyve.jp"
}

variable "instance_type" {
  description = "Staging EC2 instance type. Increase to t3.small if memory pressure is observed."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root volume size. Twenty GiB is sufficient because PostgreSQL and uploaded files are external."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size_gib >= 20 && var.root_volume_size_gib <= 100
    error_message = "root_volume_size_gib must be between 20 and 100."
  }
}

variable "ssh_allowed_cidrs" {
  description = "Optional administrator CIDRs for SSH. Empty by default; prefer Session Manager."
  type        = set(string)
  default     = []
}

variable "https_listener_rule_priority" {
  description = "Priority on the existing HTTPS listener."
  type        = number
  default     = 10

  validation {
    condition     = var.https_listener_rule_priority >= 1 && var.https_listener_rule_priority <= 50000
    error_message = "Listener rule priority must be between 1 and 50000."
  }
}

variable "http_listener_rule_priority" {
  description = "Priority on the existing HTTP listener."
  type        = number
  default     = 10

  validation {
    condition     = var.http_listener_rule_priority >= 1 && var.http_listener_rule_priority <= 50000
    error_message = "Listener rule priority must be between 1 and 50000."
  }
}
