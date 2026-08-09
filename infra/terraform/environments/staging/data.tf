data "aws_caller_identity" "current" {}

data "aws_vpc" "shared" {
  id = var.vpc_id
}

data "aws_subnet" "public" {
  id = var.public_subnet_id
}

data "aws_lb" "shared" {
  name = var.existing_alb_name
}

data "aws_lb_listener" "http" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = 80
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.shared.arn
  port              = 443
}

data "aws_route53_zone" "public" {
  name         = "${var.hosted_zone_name}."
  private_zone = false
}

data "aws_db_instance" "shared" {
  db_instance_identifier = var.existing_rds_identifier
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "external" "https_priority_check" {
  program = [
    "powershell",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "${path.module}/scripts/check_listener_priority.ps1"
  ]

  query = {
    listener_arn = data.aws_lb_listener.https.arn
    priority     = tostring(var.https_listener_rule_priority)
    hostname     = var.staging_domain
    profile      = local.aws_profile
    region       = local.aws_region
  }
}

data "external" "http_priority_check" {
  program = [
    "powershell",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "${path.module}/scripts/check_listener_priority.ps1"
  ]

  query = {
    listener_arn = data.aws_lb_listener.http.arn
    priority     = tostring(var.http_listener_rule_priority)
    hostname     = var.staging_domain
    profile      = local.aws_profile
    region       = local.aws_region
  }
}

data "external" "google_sheets_credentials_secret" {
  program = [
    "powershell",
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    "${path.module}/scripts/describe_staging_secret.ps1"
  ]

  query = {
    secret_name = var.google_sheets_credentials_secret_name
    profile     = local.aws_profile
    region      = local.aws_region
  }
}
