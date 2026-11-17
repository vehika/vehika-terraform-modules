locals {
  engine_major           = split(".", var.engine_version)[0]
  parameter_group_family = "postgres${local.engine_major}"

  # rds.force_ssl vem primeiro e não pode ser sobrescrito (validação em var.parameters).
  # apply_method = "pending-reboot": a partir do PostgreSQL 15 o valor padrão da AWS já é 1,
  # e a AWS registra o parâmetro com pending-reboot. Ela não troca só o apply_method sem
  # mudar o valor, então "immediate" gera diff perpétuo no plan. O parâmetro é dinâmico e o
  # valor não muda, logo nenhum reboot é necessário.
  parameters = concat(
    [{ name = "rds.force_ssl", value = "1", apply_method = "pending-reboot" }],
    var.parameters,
  )

  alarms = {
    cpu = {
      description = "CPU média da instância RDS ${var.identifier} acima de ${var.cpu_alarm_threshold}%."
      metric_name = "CPUUtilization"
      statistic   = "Average"
      comparison  = "GreaterThanThreshold"
      threshold   = var.cpu_alarm_threshold
    }
    freeable-memory = {
      description = "Memória livre da instância RDS ${var.identifier} abaixo de ${var.freeable_memory_alarm_threshold} bytes."
      metric_name = "FreeableMemory"
      statistic   = "Average"
      comparison  = "LessThanThreshold"
      threshold   = var.freeable_memory_alarm_threshold
    }
    free-storage = {
      description = "Armazenamento livre da instância RDS ${var.identifier} abaixo de ${var.free_storage_alarm_threshold} bytes."
      metric_name = "FreeStorageSpace"
      statistic   = "Minimum"
      comparison  = "LessThanThreshold"
      threshold   = var.free_storage_alarm_threshold
    }
    connections = {
      description = "Conexões abertas na instância RDS ${var.identifier} acima de ${var.connections_alarm_threshold}."
      metric_name = "DatabaseConnections"
      statistic   = "Maximum"
      comparison  = "GreaterThanThreshold"
      threshold   = var.connections_alarm_threshold
    }
  }
}

resource "aws_db_subnet_group" "this" {
  name        = var.identifier
  description = "Subnets da instância RDS ${var.identifier}."
  subnet_ids  = var.subnet_ids
  tags        = var.tags
}

# name_prefix com create_before_destroy: uma troca do grupo (ex.: de VPC)
# cria o novo antes de soltar o antigo, sem colisão de nome.
resource "aws_security_group" "this" {
  name_prefix = "${var.identifier}-"
  description = "Instancia RDS ${var.identifier}: entrada so dos security groups autorizados."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = var.identifier })

  lifecycle {
    create_before_destroy = true
  }
}

# Sem regra de saída: o banco só responde a conexões abertas pelos clientes.
resource "aws_vpc_security_group_ingress_rule" "allowed" {
  for_each = var.allowed_security_groups

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL a partir de ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
  tags                         = merge(var.tags, { Name = "${var.identifier}-${each.key}" })
}

resource "aws_db_parameter_group" "this" {
  name        = "${var.identifier}-${local.parameter_group_family}"
  family      = local.parameter_group_family
  description = "Parametros da instancia RDS ${var.identifier} (TLS obrigatorio)."
  tags        = var.tags

  dynamic "parameter" {
    for_each = local.parameters

    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "exports" {
  for_each = toset(var.enabled_cloudwatch_logs_exports)

  name              = "/aws/rds/instance/${var.identifier}/${each.key}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_group_kms_key_arn
  tags              = var.tags
}

resource "aws_db_instance" "this" {
  identifier                  = var.identifier
  engine                      = "postgres"
  engine_version              = var.engine_version
  engine_lifecycle_support    = var.engine_lifecycle_support
  instance_class              = var.instance_class
  auto_minor_version_upgrade  = var.auto_minor_version_upgrade
  allow_major_version_upgrade = false

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name                       = var.db_name
  username                      = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.master_user_secret_kms_key_arn
  port                          = var.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = concat([aws_security_group.this.id], var.additional_security_group_ids)
  publicly_accessible    = var.publicly_accessible
  multi_az               = var.multi_az
  network_type           = "IPV4"
  ca_cert_identifier     = var.ca_cert_identifier
  parameter_group_name   = aws_db_parameter_group.this.name

  iam_database_authentication_enabled = var.iam_database_authentication_enabled

  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = coalesce(var.final_snapshot_identifier, "${var.identifier}-final")
  apply_immediately         = var.apply_immediately

  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? var.performance_insights_kms_key_arn : null

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.exports]
}

# Usa o argumento region do provider 6: o recurso nasce na região de destino
# sem exigir um provider com alias do consumidor.
resource "aws_db_instance_automated_backups_replication" "this" {
  count = var.backup_replication_enabled ? 1 : 0

  region                 = var.backup_replication_region
  source_db_instance_arn = aws_db_instance.this.arn
  kms_key_id             = var.backup_replication_kms_key_arn
  retention_period       = coalesce(var.backup_replication_retention_period, var.backup_retention_period)
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.identifier}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric_name
  statistic           = each.value.statistic
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = "missing"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = var.tags

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }
}
