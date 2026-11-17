output "alb_dns_name" {
  description = "Nome DNS do ALB, alvo do CNAME do domínio da API."
  value       = module.alb.dns_name
}

output "api_service_name" {
  description = "Nome do serviço ECS da API."
  value       = module.api.service_name
}

output "worker_service_name" {
  description = "Nome do serviço ECS do worker."
  value       = module.worker.service_name
}

output "database_address" {
  description = "Hostname da instância RDS."
  value       = module.database.address
}

output "database_master_user_secret_arn" {
  description = "ARN do segredo da senha master, gerenciado pelo RDS."
  value       = module.database.master_user_secret_arn
}
