output "address" {
  description = "Hostname da instância."
  value       = module.database.address
}

output "master_user_secret_arn" {
  description = "ARN do segredo da senha master, gerenciado pelo RDS."
  value       = module.database.master_user_secret_arn
}

output "security_group_id" {
  description = "ID do security group da instância."
  value       = module.database.security_group_id
}
