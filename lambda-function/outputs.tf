output "function_name" {
  description = "Nome da função Lambda."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "ARN da função Lambda."
  value       = aws_lambda_function.this.arn
}

output "invoke_arn" {
  description = "ARN de invocação da função, usado por integrações do API Gateway."
  value       = aws_lambda_function.this.invoke_arn
}

output "role_name" {
  description = "Nome da role de execução da função."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "ARN da role de execução da função."
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "Nome do log group da função."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN do log group da função (sem o sufixo :*)."
  value       = aws_cloudwatch_log_group.this.arn
}

output "error_alarm_name" {
  description = "Nome do alarme de erros da função."
  value       = aws_cloudwatch_metric_alarm.errors.alarm_name
}

output "error_alarm_arn" {
  description = "ARN do alarme de erros da função."
  value       = aws_cloudwatch_metric_alarm.errors.arn
}
