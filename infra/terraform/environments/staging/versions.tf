terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket       = "butterfly-room-terraform-state-137775584467"
    key          = "butterfly-room/staging/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
    profile      = "butterfly-room-staging"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}
