output "function_name" {
  description = "Nome da função Lambda criada."
  value       = module.function.function_name
}

output "function_arn" {
  description = "ARN da função Lambda criada."
  value       = module.function.function_arn
}

output "role_arn" {
  description = "ARN da role de execução."
  value       = module.function.role_arn
}

output "log_group_name" {
  description = "Nome do log group da função."
  value       = module.function.log_group_name
}

output "error_alarm_name" {
  description = "Nome do alarme de erros."
  value       = module.function.error_alarm_name
}
