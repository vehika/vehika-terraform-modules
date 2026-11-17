output "service_name" {
  description = "Nome do serviço criado pelo módulo ecs-service."
  value       = module.api.service_name
}

output "database_identifier" {
  description = "Identificador da instância criada pelo módulo rds-postgres."
  value       = module.database.identifier
}

output "target_group_name" {
  description = "Nome do target group da API criado pelo módulo alb."
  value       = module.alb.target_group_names["api"]
}
