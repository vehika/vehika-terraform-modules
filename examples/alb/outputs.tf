output "dns_name" {
  description = "Nome DNS do ALB, alvo do CNAME do domínio."
  value       = module.alb.dns_name
}

output "security_group_id" {
  description = "ID do security group do ALB."
  value       = module.alb.security_group_id
}

output "target_group_arns" {
  description = "ARNs dos target groups, por chave."
  value       = module.alb.target_group_arns
}
