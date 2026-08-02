resource "aws_lb_target_group" "app" {
  name                          = "${local.name_prefix}-tg"
  port                          = 3000
  protocol                      = "HTTP"
  target_type                   = "instance"
  vpc_id                        = data.aws_vpc.shared.id
  deregistration_delay          = 300
  load_balancing_algorithm_type = "round_robin"
  slow_start                    = 0

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/up"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  stickiness {
    enabled = false
    type    = "lb_cookie"
  }
}

resource "aws_lb_listener_rule" "https_staging" {
  listener_arn = data.aws_lb_listener.https.arn
  priority     = var.https_listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    host_header {
      values = [var.staging_domain]
    }
  }

  lifecycle {
    precondition {
      condition     = data.external.https_priority_check.result.available == "true"
      error_message = "The requested HTTPS listener priority is already used by another host rule."
    }
  }

  depends_on = [aws_lb_listener_certificate.staging]
}

resource "aws_lb_listener_rule" "http_staging_redirect" {
  listener_arn = data.aws_lb_listener.http.arn
  priority     = var.http_listener_rule_priority

  action {
    type = "redirect"

    redirect {
      host        = "#{host}"
      path        = "/#{path}"
      port        = "443"
      protocol    = "HTTPS"
      query       = "#{query}"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = [var.staging_domain]
    }
  }

  lifecycle {
    precondition {
      condition     = data.external.http_priority_check.result.available == "true"
      error_message = "The requested HTTP listener priority is already used by another host rule."
    }
  }
}
