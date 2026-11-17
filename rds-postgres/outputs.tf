output "identifier" {
  description = "Identificador da instância RDS."
  value       = aws_db_instance.this.identifier
}

output "arn" {
  description = "ARN da instância RDS."
  value       = aws_db_instance.this.arn
}

output "resource_id" {
  description = "ID de recurso da instância (db-...), usado em políticas de autenticação IAM."
  value       = aws_db_instance.this.resource_id
}

output "address" {
  description = "Hostname da instância."
  value       = aws_db_instance.this.address
}

output "endpoint" {
  description = "Endpoint da instância no formato host:porta."
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "Porta do PostgreSQL."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Nome do banco criado com a instância (nulo quando não informado)."
  value       = aws_db_instance.this.db_name
}

output "master_username" {
  description = "Usuário master."
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "ARN do segredo do Secrets Manager com a senha master, gerenciado pelo RDS. O valor nunca passa pelo Terraform."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "security_group_id" {
  description = "ID do security group da instância."
  value       = aws_security_group.this.id
}

output "db_subnet_group_name" {
  description = "Nome do subnet group."
  value       = aws_db_subnet_group.this.name
}

output "parameter_group_name" {
  description = "Nome do parameter group (com rds.force_ssl = 1)."
  value       = aws_db_parameter_group.this.name
}

output "log_group_names" {
  description = "Log groups dos logs exportados, por tipo."
  value       = { for log_type, log_group in aws_cloudwatch_log_group.exports : log_type => log_group.name }
}

output "backup_replication_id" {
  description = "ID (ARN) dos backups automáticos replicados na região de destino (nulo quando a replicação está desligada)."
  value       = one(aws_db_instance_automated_backups_replication.this[*].id)
}

output "alarm_names" {
  description = "Nomes dos alarmes, por chave (cpu, freeable-memory, free-storage, connections)."
  value       = { for alarm_key, alarm in aws_cloudwatch_metric_alarm.this : alarm_key => alarm.alarm_name }
}

output "alarm_arns" {
  description = "ARNs dos alarmes, por chave (cpu, freeable-memory, free-storage, connections)."
  value       = { for alarm_key, alarm in aws_cloudwatch_metric_alarm.this : alarm_key => alarm.arn }
}
