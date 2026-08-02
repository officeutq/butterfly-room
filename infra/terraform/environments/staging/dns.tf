resource "aws_acm_certificate" "staging" {
  domain_name       = var.staging_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.staging.domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.public.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "staging" {
  certificate_arn         = aws_acm_certificate.staging.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_lb_listener_certificate" "staging" {
  listener_arn    = data.aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate_validation.staging.certificate_arn
}

resource "aws_route53_record" "staging" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = var.staging_domain
  type    = "A"

  alias {
    name                   = data.aws_lb.shared.dns_name
    zone_id                = data.aws_lb.shared.zone_id
    evaluate_target_health = true
  }
}
