output "service_name" {
  description = "Nome do serviço ECS."
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ARN do serviço ECS."
  value       = aws_ecs_service.this.id
}

output "task_definition_arn" {
  description = "ARN da task definition (com revisão)."
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  description = "Família da task definition."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_revision" {
  description = "Revisão da task definition."
  value       = aws_ecs_task_definition.this.revision
}

output "task_role_name" {
  description = "Nome da role da tarefa (usada pela aplicação)."
  value       = aws_iam_role.task.name
}

output "task_role_arn" {
  description = "ARN da role da tarefa (usada pela aplicação)."
  value       = aws_iam_role.task.arn
}

output "execution_role_name" {
  description = "Nome da role de execução (usada pelo ECS)."
  value       = aws_iam_role.execution.name
}

output "execution_role_arn" {
  description = "ARN da role de execução (usada pelo ECS)."
  value       = aws_iam_role.execution.arn
}

output "security_group_id" {
  description = "ID do security group das tarefas."
  value       = aws_security_group.this.id
}

output "log_group_name" {
  description = "Nome do log group do contêiner."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN do log group do contêiner (sem o sufixo :*)."
  value       = aws_cloudwatch_log_group.this.arn
}

output "autoscaling_target_resource_id" {
  description = "resource_id do alvo do Application Auto Scaling (nulo sem autoscaling)."
  value       = one(aws_appautoscaling_target.this[*].resource_id)
}

output "alarm_names" {
  description = "Nomes dos alarmes, por chave (cpu, memory)."
  value       = { for alarm_key, alarm in aws_cloudwatch_metric_alarm.this : alarm_key => alarm.alarm_name }
}

output "alarm_arns" {
  description = "ARNs dos alarmes, por chave (cpu, memory)."
  value       = { for alarm_key, alarm in aws_cloudwatch_metric_alarm.this : alarm_key => alarm.arn }
}
