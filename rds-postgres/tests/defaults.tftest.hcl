mock_provider "aws" {
  override_during = plan
}

variables {
  identifier = "example-db"
  vpc_id     = "vpc-0example"
  subnet_ids = ["subnet-0example1", "subnet-0example2"]
}

run "instance_defaults" {
  command = plan

  assert {
    condition     = aws_db_instance.this.engine == "postgres" && aws_db_instance.this.engine_version == "17"
    error_message = "O padrão deve ser PostgreSQL 17."
  }

  assert {
    condition     = aws_db_instance.this.instance_class == "db.t4g.micro"
    error_message = "A classe padrão deve ser db.t4g.micro."
  }

  assert {
    condition     = aws_db_instance.this.multi_az == false && aws_db_instance.this.publicly_accessible == false
    error_message = "Por padrão a instância é single-AZ e sem acesso público."
  }

  assert {
    condition     = aws_db_instance.this.storage_type == "gp3" && aws_db_instance.this.allocated_storage == 20 && aws_db_instance.this.max_allocated_storage == 100
    error_message = "Armazenamento padrão: gp3, 20 GiB com autoscaling até 100 GiB."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted
    error_message = "O armazenamento deve ser criptografado."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.password == null && aws_db_instance.this.username == "postgres"
    error_message = "A senha master deve ser gerenciada pelo RDS no Secrets Manager, sem senha no Terraform."
  }

  assert {
    condition     = aws_db_instance.this.engine_lifecycle_support == "open-source-rds-extended-support-disabled"
    error_message = "O suporte estendido pago deve vir desligado."
  }

  assert {
    condition     = aws_db_instance.this.performance_insights_enabled == false && length(aws_db_instance.this.enabled_cloudwatch_logs_exports) == 0
    error_message = "Performance Insights e exportação de logs devem vir desligados."
  }

  assert {
    condition     = aws_db_instance.this.allow_major_version_upgrade == false && aws_db_instance.this.auto_minor_version_upgrade
    error_message = "Só minor automático; major nunca sem mudança explícita."
  }
}

run "data_protection" {
  command = plan

  assert {
    condition     = aws_db_instance.this.backup_retention_period == 14
    error_message = "O PITR padrão deve reter 14 dias."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection && aws_db_instance.this.skip_final_snapshot == false && aws_db_instance.this.final_snapshot_identifier == "example-db-final"
    error_message = "Deletion protection e snapshot final devem vir ligados."
  }

  assert {
    condition     = aws_db_instance.this.delete_automated_backups == false && aws_db_instance.this.copy_tags_to_snapshot
    error_message = "Os backups automáticos devem sobreviver à instância e os snapshots devem herdar as tags."
  }

  assert {
    condition     = length(aws_db_instance_automated_backups_replication.this) == 0
    error_message = "Por padrão não há replicação entre regiões."
  }
}

run "tls_parameter_group" {
  command = plan

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres17" && aws_db_parameter_group.this.name == "example-db-postgres17"
    error_message = "O parameter group deve ser da família postgres17 e se chamar <identifier>-postgres17."
  }

  assert {
    condition     = [for parameter in aws_db_parameter_group.this.parameter : parameter.value if parameter.name == "rds.force_ssl"] == ["1"]
    error_message = "rds.force_ssl deve ser 1."
  }

  assert {
    condition     = aws_db_instance.this.parameter_group_name == "example-db-postgres17"
    error_message = "A instância deve usar o parameter group do módulo."
  }
}

run "network" {
  command = plan

  assert {
    condition     = aws_db_subnet_group.this.name == "example-db" && aws_db_subnet_group.this.subnet_ids == toset(["subnet-0example1", "subnet-0example2"])
    error_message = "O subnet group deve usar as subnets informadas."
  }

  assert {
    condition     = aws_security_group.this.name_prefix == "example-db-" && aws_security_group.this.vpc_id == "vpc-0example"
    error_message = "O security group deve ser criado na VPC informada."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.allowed) == 0
    error_message = "Sem allowed_security_groups, nenhuma entrada deve existir."
  }

  assert {
    condition     = aws_db_instance.this.port == 5432
    error_message = "A porta padrão deve ser 5432."
  }
}

run "alarms" {
  command = plan

  assert {
    condition     = keys(aws_cloudwatch_metric_alarm.this) == ["connections", "cpu", "free-storage", "freeable-memory"]
    error_message = "Devem existir os alarmes de CPU, memória livre, armazenamento livre e conexões."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu"].alarm_name == "example-db-cpu" && aws_cloudwatch_metric_alarm.this["cpu"].metric_name == "CPUUtilization" && aws_cloudwatch_metric_alarm.this["cpu"].threshold == 80 && aws_cloudwatch_metric_alarm.this["cpu"].comparison_operator == "GreaterThanThreshold"
    error_message = "Alarme de CPU: CPUUtilization > 80."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["freeable-memory"].metric_name == "FreeableMemory" && aws_cloudwatch_metric_alarm.this["freeable-memory"].threshold == 104857600 && aws_cloudwatch_metric_alarm.this["freeable-memory"].comparison_operator == "LessThanThreshold"
    error_message = "Alarme de memória: FreeableMemory < 100 MiB."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["free-storage"].metric_name == "FreeStorageSpace" && aws_cloudwatch_metric_alarm.this["free-storage"].threshold == 2147483648 && aws_cloudwatch_metric_alarm.this["free-storage"].statistic == "Minimum"
    error_message = "Alarme de armazenamento: FreeStorageSpace mínimo < 2 GiB."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["connections"].metric_name == "DatabaseConnections" && aws_cloudwatch_metric_alarm.this["connections"].threshold == 70
    error_message = "Alarme de conexões: DatabaseConnections > 70."
  }

  assert {
    condition     = alltrue([for alarm in values(aws_cloudwatch_metric_alarm.this) : alarm.namespace == "AWS/RDS" && alarm.dimensions == tomap({ DBInstanceIdentifier = "example-db" }) && alarm.period == 300 && alarm.evaluation_periods == 3])
    error_message = "Todos os alarmes devem observar AWS/RDS da instância, em 3 períodos de 300 s."
  }

  assert {
    condition     = alltrue([for alarm in values(aws_cloudwatch_metric_alarm.this) : length(alarm.alarm_actions) == 0 && length(alarm.ok_actions) == 0])
    error_message = "Por padrão os alarmes não têm ações."
  }
}
