mock_provider "aws" {
  override_during = plan
}

variables {
  name            = "example-alb"
  vpc_id          = "vpc-0example"
  subnet_ids      = ["subnet-0example1", "subnet-0example2"]
  certificate_arn = "arn:aws:acm:us-east-1:${format("%012d", 0)}:certificate/example-certificate"
}

run "api_target_group" {
  command = plan

  variables {
    target_groups = {
      api = { port = 3000, health_check = { path = "/health" } }
    }
    default_target_group   = "api"
    target_security_groups = { api = { security_group_id = "sg-0exampleapi", port = 3000 } }
  }

  assert {
    condition     = aws_lb_target_group.this["api"].name == "example-alb-api" && aws_lb_target_group.this["api"].target_type == "ip" && aws_lb_target_group.this["api"].port == 3000 && aws_lb_target_group.this["api"].protocol == "HTTP"
    error_message = "O target group deve ser do tipo ip, HTTP, na porta informada, com nome <name>-<chave>."
  }

  assert {
    condition     = aws_lb_target_group.this["api"].health_check[0].path == "/health" && aws_lb_target_group.this["api"].health_check[0].matcher == "200-399" && aws_lb_target_group.this["api"].health_check[0].port == "traffic-port"
    error_message = "O health check deve usar o caminho informado, matcher 200-399 e a porta do tráfego."
  }

  assert {
    condition     = length(aws_lb_listener.https.default_action) == 1 && aws_lb_listener.https.default_action[0].type == "forward"
    error_message = "Com default_target_group, o HTTPS encaminha para ele."
  }

  assert {
    condition     = keys(aws_vpc_security_group_egress_rule.targets) == ["api"] && aws_vpc_security_group_egress_rule.targets["api"].referenced_security_group_id == "sg-0exampleapi" && aws_vpc_security_group_egress_rule.targets["api"].from_port == 3000 && aws_vpc_security_group_egress_rule.targets["api"].to_port == 3000 && aws_vpc_security_group_egress_rule.targets["api"].cidr_ipv4 == null
    error_message = "A saída do ALB deve ir só para o security group dos alvos, na porta do contêiner."
  }

  assert {
    condition     = keys(aws_cloudwatch_metric_alarm.healthy_hosts) == ["api"] && aws_cloudwatch_metric_alarm.healthy_hosts["api"].alarm_name == "example-alb-api-healthy-hosts" && aws_cloudwatch_metric_alarm.healthy_hosts["api"].metric_name == "HealthyHostCount" && aws_cloudwatch_metric_alarm.healthy_hosts["api"].threshold == 1 && aws_cloudwatch_metric_alarm.healthy_hosts["api"].comparison_operator == "LessThanThreshold"
    error_message = "Cada target group deve ter o alarme <name>-<chave>-healthy-hosts (menos de 1 alvo saudável)."
  }
}

run "listener_rules_and_certificates" {
  command = plan

  variables {
    target_groups = {
      api   = { port = 3000 }
      admin = { name = "example-admin", port = 3001 }
    }
    default_target_group = "api"
    listener_rules = {
      admin = { priority = 10, target_group = "admin", host_headers = ["admin.example.com"], path_patterns = ["/admin/*"] }
    }
    additional_certificate_arns = ["arn:aws:acm:us-east-1:${format("%012d", 0)}:certificate/example-certificate-2"]
    hsts_header_value           = "max-age=31536000; includeSubDomains"
  }

  assert {
    condition     = aws_lb_target_group.this["admin"].name == "example-admin"
    error_message = "O name informado deve sobrescrever o nome do target group."
  }

  assert {
    condition     = aws_lb_listener_rule.this["admin"].priority == 10 && length(aws_lb_listener_rule.this["admin"].condition) == 2
    error_message = "A regra deve ter a prioridade e as duas condições."
  }

  assert {
    condition     = length(aws_lb_listener_certificate.additional) == 1 && aws_lb_listener_certificate.additional[0].certificate_arn == "arn:aws:acm:us-east-1:${format("%012d", 0)}:certificate/example-certificate-2"
    error_message = "Certificados extras devem ir para o listener HTTPS."
  }

  assert {
    condition     = aws_lb_listener.https.routing_http_response_strict_transport_security_header_value == "max-age=31536000; includeSubDomains"
    error_message = "O HSTS informado deve ser aplicado no listener HTTPS."
  }
}

run "access_logs_enabled" {
  command = plan

  variables {
    access_logs_bucket = "example-alb-logs"
  }

  assert {
    condition     = length(aws_lb.this.access_logs) == 1 && aws_lb.this.access_logs[0].enabled && aws_lb.this.access_logs[0].bucket == "example-alb-logs" && aws_lb.this.access_logs[0].prefix == "example-alb"
    error_message = "Com bucket, os access logs ligam com o prefixo padrão igual ao nome do ALB."
  }
}

run "access_logs_custom_prefix" {
  command = plan

  variables {
    access_logs_bucket = "example-alb-logs"
    access_logs_prefix = "alb/api"
  }

  assert {
    condition     = aws_lb.this.access_logs[0].prefix == "alb/api"
    error_message = "O prefixo informado deve ser usado."
  }
}

run "waf_customization" {
  command = plan

  variables {
    waf_rate_limit           = 500
    waf_rate_limit_window    = 60
    waf_forwarded_ip_header  = "X-Forwarded-For"
    waf_rule_count_overrides = { common = ["SizeRestrictions_BODY"] }
    waf_log_destination_arn  = "arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:aws-waf-logs-example"
  }

  assert {
    condition = alltrue([
      for rule in aws_wafv2_web_acl.this[0].rule : rule.statement[0].rate_based_statement[0].limit == 500 && rule.statement[0].rate_based_statement[0].evaluation_window_sec == 60 && rule.statement[0].rate_based_statement[0].aggregate_key_type == "FORWARDED_IP" && rule.statement[0].rate_based_statement[0].forwarded_ip_config[0].header_name == "X-Forwarded-For"
      if rule.name == "rate-limit-per-ip"
    ])
    error_message = "Limite, janela e cabeçalho do IP encaminhado devem ser repassados."
  }

  assert {
    condition = alltrue([
      for rule in aws_wafv2_web_acl.this[0].rule : [for override in rule.statement[0].managed_rule_group_statement[0].rule_action_override : override.name] == ["SizeRestrictions_BODY"]
      if rule.name == "AWSManagedRulesCommonRuleSet"
    ])
    error_message = "A regra informada deve passar a só contar no grupo Common."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 1 && aws_wafv2_web_acl_logging_configuration.this[0].log_destination_configs == toset(["arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:aws-waf-logs-example"])
    error_message = "Com destino, os logs do WAF devem ser configurados."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this[0].redacted_fields) == 2
    error_message = "Os cabeçalhos authorization e cookie devem ser omitidos dos logs."
  }
}

run "waf_disabled_internal" {
  command = plan

  variables {
    waf_enabled         = false
    internal            = true
    deletion_protection = false
    ingress_cidr_blocks = ["10.0.0.0/16", "10.1.0.0/16"]
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 0 && length(aws_wafv2_web_acl_association.this) == 0 && output.web_acl_arn == null
    error_message = "Sem WAF, nada do WAF é criado."
  }

  assert {
    condition     = aws_lb.this.internal && aws_lb.this.enable_deletion_protection == false
    error_message = "internal e deletion_protection devem ser repassados."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 4
    error_message = "Cada CIDR deve ganhar entrada em 80 e 443."
  }
}

run "alarm_customization" {
  command = plan

  variables {
    elb_5xx_alarm_threshold    = 5
    target_5xx_alarm_threshold = 20
    latency_alarm_threshold    = 1.5
    alarm_period               = 60
    alarm_evaluation_periods   = 5
    alarm_actions              = ["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]
    ok_actions                 = ["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]
    tags                       = { service = "example" }
    target_groups              = { api = { port = 3000 } }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["elb-5xx"].threshold == 5 && aws_cloudwatch_metric_alarm.this["target-5xx"].threshold == 20 && aws_cloudwatch_metric_alarm.this["latency"].threshold == 1.5 && aws_cloudwatch_metric_alarm.this["latency"].period == 60 && aws_cloudwatch_metric_alarm.this["latency"].evaluation_periods == 5
    error_message = "Limites e períodos dos alarmes devem ser repassados."
  }

  assert {
    condition     = alltrue([for alarm in concat(values(aws_cloudwatch_metric_alarm.this), values(aws_cloudwatch_metric_alarm.healthy_hosts)) : alarm.alarm_actions == toset(["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]) && alarm.ok_actions == toset(["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"])])
    error_message = "As ações devem ir para todos os alarmes."
  }

  assert {
    condition = alltrue([
      aws_lb.this.tags == tomap({ service = "example" }),
      aws_lb_listener.http.tags == tomap({ service = "example" }),
      aws_lb_listener.https.tags == tomap({ service = "example" }),
      aws_lb_target_group.this["api"].tags == tomap({ service = "example" }),
      aws_wafv2_web_acl.this[0].tags == tomap({ service = "example" }),
      aws_security_group.this.tags["service"] == "example",
      aws_cloudwatch_metric_alarm.this["latency"].tags == tomap({ service = "example" }),
    ])
    error_message = "As tags devem ir para todos os recursos que aceitam tags."
  }
}
