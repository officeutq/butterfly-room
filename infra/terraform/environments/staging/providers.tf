provider "aws" {
  profile = "butterfly-room-staging"
  region  = "ap-northeast-1"

  allowed_account_ids = ["137775584467"]

  default_tags {
    tags = {
      app        = "butterfly-room"
      env        = "staging"
      managed_by = "terraform"
    }
  }
}
