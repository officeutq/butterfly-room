locals {
  name_prefix = "butterfly-room-staging"
  aws_profile = "butterfly-room-staging"
  aws_region  = "ap-northeast-1"

  systemd_directory = "${path.module}/../../../../ops/systemd"
}
