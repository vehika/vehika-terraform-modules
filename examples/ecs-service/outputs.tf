output "cluster_arn" {
  description = "ARN do cluster ECS."
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "Nome do serviço ECS."
  value       = module.worker.service_name
}

output "task_role_arn" {
  description = "ARN da role da tarefa."
  value       = module.worker.task_role_arn
}

output "security_group_id" {
  description = "ID do security group das tarefas."
  value       = module.worker.security_group_id
}
