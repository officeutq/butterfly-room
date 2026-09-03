resource "aws_s3_bucket" "app" {
  bucket        = "butterfly-room-staging"
  force_destroy = false
}

resource "aws_s3_bucket_ownership_controls" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT"]
    allowed_origins = ["https://${var.staging_domain}"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# Only disposable image-upload verification data, never regular attachments.
# Delayed PUTs and noncurrent versions can survive application-level deletion.
resource "aws_s3_bucket_lifecycle_configuration" "image_upload_verification" {
  bucket = aws_s3_bucket.app.id

  rule {
    id     = "expire-image-upload-verification"
    status = "Enabled"
    filter {
      prefix = "image-upload-verification/"
    }
    expiration {
      days = 1
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  rule {
    id     = "remove-image-upload-verification-delete-markers"
    status = "Enabled"
    filter {
      prefix = "image-upload-verification/"
    }
    expiration {
      expired_object_delete_marker = true
    }
  }
}
