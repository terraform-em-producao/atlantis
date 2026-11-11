data "aws_route53_zone" "org" {
  name = var.dominio
}

locals {
  host = "atlantis.${var.dominio}"
  url  = "https://${local.host}"
}

resource "aws_acm_certificate" "atlantis" {
  domain_name       = local.host
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validacao" {
  for_each = {
    for o in aws_acm_certificate.atlantis.domain_validation_options : o.domain_name => o
  }

  zone_id = data.aws_route53_zone.org.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "atlantis" {
  certificate_arn         = aws_acm_certificate.atlantis.arn
  validation_record_fqdns = [for r in aws_route53_record.validacao : r.fqdn]
}

# Público de propósito: o GitHub precisa alcançar o webhook. A proteção é o
# secret do webhook, o HTTPS e a lista de repos atendidos.
#trivy:ignore:AWS-0053
resource "aws_lb" "atlantis" {
  name                       = "atlantis"
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.publica[*].id
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "atlantis" {
  name        = "atlantis"
  port        = 4141
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.atlantis.id

  deregistration_delay = 30

  health_check {
    path    = "/healthz"
    matcher = "200"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.atlantis.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.atlantis.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.atlantis.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.atlantis.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_route53_record" "atlantis" {
  zone_id = data.aws_route53_zone.org.zone_id
  name    = local.host
  type    = "A"

  alias {
    name                   = aws_lb.atlantis.dns_name
    zone_id                = aws_lb.atlantis.zone_id
    evaluate_target_health = true
  }
}
