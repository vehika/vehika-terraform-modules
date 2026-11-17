output "arn" {
  description = "ARN do ALB."
  value       = aws_lb.this.arn
}

output "arn_suffix" {
  description = "Sufixo do ARN do ALB (dimensão LoadBalancer das métricas)."
  value       = aws_lb.this.arn_suffix
}

output "dns_name" {
  description = "Nome DNS do ALB (alvo do CNAME do domínio)."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Hosted zone do ALB, para registros alias."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ID do security group do ALB (use em allowed_security_groups do ecs-service)."
  value       = aws_security_group.this.id
}

output "http_listener_arn" {
  description = "ARN do listener HTTP (redireciona para HTTPS)."
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN do listener HTTPS."
  value       = aws_lb_listener.https.arn
}

# Depende dos listeners e regras: o ECS recusa registrar um serviço num target
# group que ainda não está associado ao load balancer.
output "target_group_arns" {
  description = "ARNs dos target groups, por chave. Disponíveis só depois que o listener e as regras existem."
  value       = { for target_key, target_group in aws_lb_target_group.this : target_key => target_group.arn }

  depends_on = [
    aws_lb_listener.https,
    aws_lb_listener_rule.this,
  ]
}

output "target_group_arn_suffixes" {
  description = "Sufixos dos ARNs dos target groups, por chave (dimensão TargetGroup das métricas)."
  value       = { for target_key, target_group in aws_lb_target_group.this : target_key => target_group.arn_suffix }
}

output "target_group_names" {
  description = "Nomes dos target groups, por chave."
  value       = { for target_key, target_group in aws_lb_target_group.this : target_key => target_group.name }
}

output "web_acl_arn" {
  description = "ARN da web ACL do WAF (nulo com waf_enabled = false)."
  value       = one(aws_wafv2_web_acl.this[*].arn)
}

output "web_acl_name" {
  description = "Nome da web ACL do WAF (nulo com waf_enabled = false)."
  value       = one(aws_wafv2_web_acl.this[*].name)
}

output "alarm_names" {
  description = "Nomes dos alarmes, por chave (elb-5xx, target-5xx, latency e <target group>-healthy-hosts)."
  value = merge(
    { for alarm_key, alarm in aws_cloudwatch_metric_alarm.this : alarm_key => alarm.alarm_name },
    { for target_key, alarm in aws_cloudwatch_metric_alarm.healthy_hosts : "${target_key}-healthy-hosts" => alarm.alarm_name },
  )
}

output "alarm_arns" {
  description = "ARNs dos alarmes, por chave (elb-5xx, target-5xx, latency e <target group>-healthy-hosts)."
  value = merge(
    { for alarm_key, alarm in aws_cloudwatch_metric_alarm.this : alarm_key => alarm.arn },
    { for target_key, alarm in aws_cloudwatch_metric_alarm.healthy_hosts : "${target_key}-healthy-hosts" => alarm.arn },
  )
}
