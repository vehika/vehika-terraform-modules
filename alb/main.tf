locals {
  target_group_names = {
    for target_key, target_group in var.target_groups : target_key => coalesce(target_group.name, "${var.name}-${target_key}")
  }

  ingress_rules = merge([
    for index, cidr in var.ingress_cidr_blocks : {
      "http-${index}"  = { cidr = cidr, port = 80, description = "HTTP de ${cidr} (redireciona para HTTPS)" }
      "https-${index}" = { cidr = cidr, port = 443, description = "HTTPS de ${cidr}" }
    }
  ]...)

  managed_rule_groups = {
    ip_reputation = {
      priority = 10
      name     = "AWSManagedRulesAmazonIpReputationList"
    }
    common = {
      priority = 20
      name     = "AWSManagedRulesCommonRuleSet"
    }
    known_bad_inputs = {
      priority = 30
      name     = "AWSManagedRulesKnownBadInputsRuleSet"
    }
  }

  alarms = {
    elb-5xx = {
      description        = "Respostas 5xx geradas pelo ALB ${var.name}."
      metric_name        = "HTTPCode_ELB_5XX_Count"
      statistic          = "Sum"
      extended_statistic = null
      comparison         = "GreaterThanOrEqualToThreshold"
      threshold          = var.elb_5xx_alarm_threshold
    }
    target-5xx = {
      description        = "Respostas 5xx dos alvos do ALB ${var.name}."
      metric_name        = "HTTPCode_Target_5XX_Count"
      statistic          = "Sum"
      extended_statistic = null
      comparison         = "GreaterThanOrEqualToThreshold"
      threshold          = var.target_5xx_alarm_threshold
    }
    latency = {
      description        = "p95 do tempo de resposta dos alvos do ALB ${var.name} acima de ${var.latency_alarm_threshold} s."
      metric_name        = "TargetResponseTime"
      statistic          = null
      extended_statistic = "p95"
      comparison         = "GreaterThanThreshold"
      threshold          = var.latency_alarm_threshold
    }
  }
}

# name_prefix com create_before_destroy: uma troca do grupo cria o novo
# antes de soltar o antigo, sem colisão de nome.
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "ALB ${var.name}: entrada HTTP/HTTPS e saida so para os alvos."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

# Entrada da internet (0.0.0.0/0 por padrão) só em 80, que redireciona para
# 443, e 443; o WAF filtra o tráfego HTTP. É uma exceção declarada ao AWS-0107
# (entrada irrestrita), que o trivy 0.76 não aponta neste recurso; ver README.
resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.this.id
  description       = each.value.description
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
  tags              = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_vpc_security_group_egress_rule" "targets" {
  for_each = var.target_security_groups

  security_group_id            = aws_security_group.this.id
  description                  = "Trafego e health check para ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  referenced_security_group_id = each.value.security_group_id
  tags                         = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

# Exceção do trivy (AWS-0053, load balancer público): o ALB voltado à internet
# é a entrada da API por decisão de arquitetura, com WAF associado. Com
# internal = true o achado não se aplica.
#trivy:ignore:AWS-0053
resource "aws_lb" "this" {
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = var.internal
  ip_address_type            = "ipv4"
  subnets                    = var.subnet_ids
  security_groups            = [aws_security_group.this.id]
  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.deletion_protection
  enable_http2               = true
  drop_invalid_header_fields = true
  desync_mitigation_mode     = var.desync_mitigation_mode
  xff_header_processing_mode = "append"
  tags                       = var.tags

  dynamic "access_logs" {
    for_each = var.access_logs_bucket == null ? [] : [var.access_logs_bucket]

    content {
      bucket  = access_logs.value
      prefix  = coalesce(var.access_logs_prefix, var.name)
      enabled = true
    }
  }
}

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name                 = local.target_group_names[each.key]
  vpc_id               = var.vpc_id
  target_type          = "ip"
  port                 = each.value.port
  protocol             = each.value.protocol
  protocol_version     = each.value.protocol_version
  deregistration_delay = each.value.deregistration_delay
  slow_start           = each.value.slow_start
  tags                 = var.tags

  health_check {
    enabled             = true
    path                = each.value.health_check.path
    matcher             = each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
    protocol            = each.value.protocol
    port                = "traffic-port"
  }

  lifecycle {
    precondition {
      condition     = length(local.target_group_names[each.key]) <= 32
      error_message = "O nome do target group (<name>-<chave> ou name) passa de 32 caracteres; informe um name mais curto."
    }
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  tags              = var.tags

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn
  tags              = var.tags

  routing_http_response_strict_transport_security_header_value = var.hsts_header_value

  dynamic "default_action" {
    for_each = var.default_target_group == null ? [] : [var.default_target_group]

    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this[default_action.value].arn
    }
  }

  dynamic "default_action" {
    for_each = var.default_target_group == null ? ["fixed-response"] : []

    content {
      type = "fixed-response"

      fixed_response {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }
}

resource "aws_lb_listener_certificate" "additional" {
  count = length(var.additional_certificate_arns)

  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = var.additional_certificate_arns[count.index]
}

resource "aws_lb_listener_rule" "this" {
  for_each = var.listener_rules

  listener_arn = aws_lb_listener.https.arn
  priority     = each.value.priority
  tags         = var.tags

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group].arn
  }

  dynamic "condition" {
    for_each = length(each.value.host_headers) == 0 ? [] : [each.value.host_headers]

    content {
      host_header {
        values = condition.value
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.path_patterns) == 0 ? [] : [each.value.path_patterns]

    content {
      path_pattern {
        values = condition.value
      }
    }
  }
}

resource "aws_wafv2_web_acl" "this" {
  count = var.waf_enabled ? 1 : 0

  name        = var.name
  description = "Web ACL do ALB ${var.name}: rate limit por IP e regras gerenciadas da AWS."
  scope       = "REGIONAL"
  tags        = var.tags

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = var.waf_rate_limit
        evaluation_window_sec = var.waf_rate_limit_window
        aggregate_key_type    = var.waf_forwarded_ip_header == null ? "IP" : "FORWARDED_IP"

        dynamic "forwarded_ip_config" {
          for_each = var.waf_forwarded_ip_header == null ? [] : [var.waf_forwarded_ip_header]

          content {
            header_name       = forwarded_ip_config.value
            fallback_behavior = "MATCH"
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit-per-ip"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = local.managed_rule_groups

    content {
      name     = rule.value.name
      priority = rule.value.priority

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"

          dynamic "rule_action_override" {
            for_each = lookup(var.waf_rule_count_overrides, rule.key, [])

            content {
              name = rule_action_override.value

              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-${rule.value.name}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.waf_enabled ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = var.waf_enabled && var.waf_log_destination_arn != null ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.this[0].arn
  log_destination_configs = [var.waf_log_destination_arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/ApplicationELB"
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  extended_statistic  = each.value.extended_statistic
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = var.tags

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "healthy_hosts" {
  for_each = var.target_groups

  alarm_name          = "${var.name}-${each.key}-healthy-hosts"
  alarm_description   = "Nenhum alvo saudável no target group ${each.key} do ALB ${var.name}."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = var.tags

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.this[each.key].arn_suffix
  }
}
