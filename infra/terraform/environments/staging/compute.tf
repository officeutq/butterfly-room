resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "Staging app access from the shared ALB"
  vpc_id      = data.aws_vpc.shared.id

  tags = {
    Name = "${local.name_prefix}-app-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = one(data.aws_lb.shared.security_groups)
  description                  = "Rails from shared ALB"
  from_port                    = 3000
  to_port                      = 3000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = var.ssh_allowed_cidrs

  security_group_id = aws_security_group.app.id
  cidr_ipv4         = each.value
  description       = "Optional administrator SSH"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS, RDS, package, and AWS service egress"
  ip_protocol       = "-1"
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name

  monitoring                  = false
  disable_api_termination     = false
  user_data_replace_on_change = false

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  credit_specification {
    cpu_credits = "standard"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    volume_size           = var.root_volume_size_gib
    volume_type           = "gp3"
  }

  volume_tags = {
    Name       = "${local.name_prefix}-app-1-root"
    app        = "butterfly-room"
    env        = "staging"
    managed_by = "terraform"
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    app_service_b64     = base64encode(file("${local.systemd_directory}/butterflyve-staging-app.service"))
    monthly_service_b64 = base64encode(file("${local.systemd_directory}/butterflyve-monthly-settlement-staging.service"))
    monthly_timer_b64   = base64encode(file("${local.systemd_directory}/butterflyve-monthly-settlement-staging.timer"))
  })

  tags = {
    Name = "${local.name_prefix}-app-1"
  }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = 3000
}
