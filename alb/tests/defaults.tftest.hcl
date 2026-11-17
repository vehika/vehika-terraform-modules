mock_provider "aws" {
  override_during = plan
}

variables {
  name            = "example-alb"
  vpc_id          = "vpc-0example"
  subnet_ids      = ["subnet-0example1", "subnet-0example2"]
  certificate_arn = "arn:aws:acm:us-east-1:${format("%012d", 0)}:certificate/example-certificate"
}

run "load_balancer_defaults" {
  command = plan

  assert {
    condition     = aws_lb.this.name == "example-alb" && aws_lb.this.load_balancer_type == "application" && aws_lb.this.internal == false
    error_message = "O padrão deve ser um ALB voltado à internet."
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields && aws_lb.this.desync_mitigation_mode == "defensive" && aws_lb.this.enable_http2
    error_message = "Cabeçalhos inválidos devem ser descartados, com mitigação de desync defensive."
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection
    error_message = "Deletion protection deve vir ligada."
  }

  assert {
    condition     = length(aws_lb.this.access_logs) == 0 || alltrue([for access_log in aws_lb.this.access_logs : access_log.enabled == false])
    error_message = "Por padrão os access logs ficam desligados."
  }

  assert {
    condition     = aws_lb.this.subnets == toset(["subnet-0example1", "subnet-0example2"])
    error_message = "O ALB deve usar as subnets informadas."
  }
}

run "listeners" {
  command = plan

  assert {
    condition     = aws_lb_listener.http.port == 80 && aws_lb_listener.http.protocol == "HTTP" && aws_lb_listener.http.default_action[0].type == "redirect"
    error_message = "O listener 80 deve só redirecionar."
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].redirect[0].port == "443" && aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS" && aws_lb_listener.http.default_action[0].redirect[0].status_code == "HTTP_301"
    error_message = "O redirecionamento deve ser 301 para HTTPS na 443."
  }

  assert {
    condition     = aws_lb_listener.https.port == 443 && aws_lb_listener.https.protocol == "HTTPS" && aws_lb_listener.https.certificate_arn == var.certificate_arn
    error_message = "O listener 443 deve usar HTTPS com o certificado informado."
  }

  assert {
    condition     = aws_lb_listener.https.ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "A política de TLS padrão deve ser a de TLS 1.3/1.2."
  }

  assert {
    condition     = aws_lb_listener.https.default_action[0].type == "fixed-response" && aws_lb_listener.https.default_action[0].fixed_response[0].status_code == "404"
    error_message = "Sem default_target_group, o HTTPS responde 404 fixo."
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener_rule.this) == 0 && length(aws_lb_listener_certificate.additional) == 0
    error_message = "Sem target_groups, regras ou certificados extras, nada disso é criado."
  }
}

run "security_group" {
  command = plan

  assert {
    condition     = keys(aws_vpc_security_group_ingress_rule.this) == ["http-0", "https-0"]
    error_message = "A entrada padrão deve ser 80 e 443."
  }

  assert {
    condition     = alltrue([for rule in values(aws_vpc_security_group_ingress_rule.this) : rule.cidr_ipv4 == "0.0.0.0/0" && rule.ip_protocol == "tcp" && contains([80, 443], rule.from_port) && rule.from_port == rule.to_port])
    error_message = "A entrada deve aceitar só TCP 80 e 443."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.targets) == 0
    error_message = "Sem target_security_groups, não há saída."
  }
}

run "waf_defaults" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 1 && aws_wafv2_web_acl.this[0].scope == "REGIONAL" && length(aws_wafv2_web_acl_association.this) == 1
    error_message = "O WAF regional deve ser criado e associado ao ALB."
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this[0].default_action[0].allow) == 1
    error_message = "A ação padrão da web ACL deve ser allow."
  }

  assert {
    condition     = toset([for rule in aws_wafv2_web_acl.this[0].rule : rule.name]) == toset(["rate-limit-per-ip", "AWSManagedRulesAmazonIpReputationList", "AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet"])
    error_message = "A web ACL deve ter o rate limit e as regras Common, KnownBadInputs e IpReputation."
  }

  assert {
    condition = alltrue([
      for rule in aws_wafv2_web_acl.this[0].rule : rule.statement[0].rate_based_statement[0].limit == 2000 && rule.statement[0].rate_based_statement[0].aggregate_key_type == "IP" && rule.statement[0].rate_based_statement[0].evaluation_window_sec == 300 && length(rule.action[0].block) == 1
      if rule.name == "rate-limit-per-ip"
    ])
    error_message = "O rate limit padrão deve bloquear acima de 2000 requisições por IP em 300 s."
  }

  assert {
    condition = alltrue([
      for rule in aws_wafv2_web_acl.this[0].rule : rule.statement[0].managed_rule_group_statement[0].vendor_name == "AWS" && length(rule.override_action[0].none) == 1 && length(rule.statement[0].managed_rule_group_statement[0].rule_action_override) == 0
      if rule.name != "rate-limit-per-ip"
    ])
    error_message = "As regras gerenciadas devem bloquear (override none) sem exceções por padrão."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 0
    error_message = "Sem destino, o WAF não registra logs."
  }
}

run "alarms" {
  command = plan

  assert {
    condition     = keys(aws_cloudwatch_metric_alarm.this) == ["elb-5xx", "latency", "target-5xx"]
    error_message = "Devem existir os alarmes de 5xx do ALB, 5xx dos alvos e latência."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["elb-5xx"].metric_name == "HTTPCode_ELB_5XX_Count" && aws_cloudwatch_metric_alarm.this["elb-5xx"].statistic == "Sum" && aws_cloudwatch_metric_alarm.this["elb-5xx"].threshold == 10
    error_message = "Alarme de 5xx do ALB: soma >= 10."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["target-5xx"].metric_name == "HTTPCode_Target_5XX_Count" && aws_cloudwatch_metric_alarm.this["target-5xx"].threshold == 10
    error_message = "Alarme de 5xx dos alvos: soma >= 10."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["latency"].metric_name == "TargetResponseTime" && aws_cloudwatch_metric_alarm.this["latency"].extended_statistic == "p95" && aws_cloudwatch_metric_alarm.this["latency"].statistic == null && aws_cloudwatch_metric_alarm.this["latency"].threshold == 2
    error_message = "Alarme de latência: p95 > 2 s."
  }

  assert {
    condition     = [for alarm_key, alarm in aws_cloudwatch_metric_alarm.this : alarm.alarm_name] == ["example-alb-elb-5xx", "example-alb-latency", "example-alb-target-5xx"] && alltrue([for alarm in values(aws_cloudwatch_metric_alarm.this) : alarm.namespace == "AWS/ApplicationELB" && alarm.treat_missing_data == "notBreaching" && alarm.evaluation_periods == 2 && alarm.period == 300])
    error_message = "Os alarmes devem se chamar <name>-<chave>, observar AWS/ApplicationELB em 2 períodos de 300 s e não disparar sem dados."
  }
}
