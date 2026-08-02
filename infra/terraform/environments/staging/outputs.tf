output "staging_domain" {
  description = "Staging application URL."
  value       = "https://${var.staging_domain}"
}

output "instance_id" {
  description = "Staging EC2 instance ID."
  value       = aws_instance.app.id
}

output "instance_public_ip" {
  description = "Ephemeral public IP. It changes after stop/start because no Elastic IP is assigned."
  value       = aws_instance.app.public_ip
}

output "target_group_arn" {
  description = "Staging target group ARN."
  value       = aws_lb_target_group.app.arn
}

output "staging_bucket_name" {
  description = "Staging Active Storage bucket."
  value       = aws_s3_bucket.app.id
}

output "shared_rds_resource_id" {
  description = "Read-only confirmation that the existing shared RDS data source resolved."
  value       = data.aws_db_instance.shared.resource_id
}
