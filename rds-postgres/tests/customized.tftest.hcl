mock_provider "aws" {
  override_during = plan
}

variables {
  identifier = "example-db"
  vpc_id     = "vpc-0example"
  subnet_ids = ["subnet-0example1", "subnet-0example2"]
}

run "multi_az_cmk_and_access" {
  command = plan

  variables {
    multi_az                       = true
    kms_key_arn                    = "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-storage"
    master_user_secret_kms_key_arn = "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-secret"
    allowed_security_groups        = { api = "sg-0exampleapi", worker = "sg-0exampleworker" }
    additional_security_group_ids  = ["sg-0exampleextra"]
    db_name                        = "example"
    backup_retention_period        = 7
    backup_window                  = "06:00-06:30"
    maintenance_window             = "sun:07:00-sun:08:00"
  }

  assert {
    condition     = aws_db_instance.this.multi_az
    error_message = "multi_az deve ser repassado."
  }

  assert {
    condition     = aws_db_instance.this.kms_key_id == "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-storage" && aws_db_instance.this.master_user_secret_kms_key_id == "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-secret"
    error_message = "As CMKs do armazenamento e do segredo devem ser repassadas."
  }

  assert {
    condition     = keys(aws_vpc_security_group_ingress_rule.allowed) == ["api", "worker"] && aws_vpc_security_group_ingress_rule.allowed["api"].referenced_security_group_id == "sg-0exampleapi" && aws_vpc_security_group_ingress_rule.allowed["api"].from_port == 5432 && aws_vpc_security_group_ingress_rule.allowed["api"].to_port == 5432
    error_message = "Cada security group autorizado deve ganhar entrada só na porta do banco."
  }

  assert {
    condition     = contains(aws_db_instance.this.vpc_security_group_ids, "sg-0exampleextra")
    error_message = "Security groups extras devem ser associados."
  }

  assert {
    condition     = aws_db_instance.this.db_name == "example" && aws_db_instance.this.backup_retention_period == 7 && aws_db_instance.this.backup_window == "06:00-06:30" && aws_db_instance.this.maintenance_window == "sun:07:00-sun:08:00"
    error_message = "Banco inicial, retenção e janelas devem ser repassados."
  }
}

run "public_access" {
  command = plan

  variables {
    publicly_accessible = true
  }

  assert {
    condition     = aws_db_instance.this.publicly_accessible
    error_message = "publicly_accessible deve ser repassado."
  }
}

run "cross_region_backup_replication" {
  command = plan

  variables {
    kms_key_arn                    = "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-storage"
    backup_replication_enabled     = true
    backup_replication_region      = "us-east-2"
    backup_replication_kms_key_arn = "arn:aws:kms:us-east-2:${format("%012d", 0)}:key/example-replica"
  }

  assert {
    condition     = length(aws_db_instance_automated_backups_replication.this) == 1
    error_message = "A replicação deve existir quando ligada."
  }

  assert {
    condition     = aws_db_instance_automated_backups_replication.this[0].region == "us-east-2" && aws_db_instance_automated_backups_replication.this[0].kms_key_id == "arn:aws:kms:us-east-2:${format("%012d", 0)}:key/example-replica"
    error_message = "A replicação deve nascer na região de destino com a chave de lá."
  }

  assert {
    condition     = aws_db_instance_automated_backups_replication.this[0].retention_period == 14
    error_message = "Sem retenção própria, a réplica deve herdar backup_retention_period."
  }
}

run "replication_custom_retention" {
  command = plan

  variables {
    backup_replication_enabled          = true
    backup_replication_region           = "us-east-2"
    backup_replication_kms_key_arn      = "arn:aws:kms:us-east-2:${format("%012d", 0)}:key/example-replica"
    backup_replication_retention_period = 7
  }

  assert {
    condition     = aws_db_instance_automated_backups_replication.this[0].retention_period == 7
    error_message = "A retenção da réplica deve ser repassada."
  }
}

run "extra_parameters_and_logs" {
  command = plan

  variables {
    engine_version                  = "17.6"
    parameters                      = [{ name = "log_min_duration_statement", value = "1000" }, { name = "shared_preload_libraries", value = "pg_stat_statements", apply_method = "pending-reboot" }]
    enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
    log_retention_in_days           = 14
    log_group_kms_key_arn           = "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-logs"
  }

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres17" && length(aws_db_parameter_group.this.parameter) == 3
    error_message = "Com minor informado, a família continua postgres17 e os parâmetros extras se somam ao rds.force_ssl."
  }

  assert {
    condition     = [for parameter in aws_db_parameter_group.this.parameter : parameter.apply_method if parameter.name == "shared_preload_libraries"] == ["pending-reboot"]
    error_message = "apply_method deve ser repassado."
  }

  assert {
    condition     = keys(aws_cloudwatch_log_group.exports) == ["postgresql", "upgrade"] && aws_cloudwatch_log_group.exports["postgresql"].name == "/aws/rds/instance/example-db/postgresql" && aws_cloudwatch_log_group.exports["postgresql"].retention_in_days == 14
    error_message = "Cada log exportado deve ter um log group com retenção criado pelo módulo."
  }

  assert {
    condition     = aws_db_instance.this.enabled_cloudwatch_logs_exports == toset(["postgresql", "upgrade"])
    error_message = "A exportação de logs deve ser repassada."
  }
}

run "alarm_customization" {
  command = plan

  variables {
    cpu_alarm_threshold         = 90
    connections_alarm_threshold = 50
    alarm_period                = 60
    alarm_evaluation_periods    = 5
    alarm_actions               = ["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]
    ok_actions                  = ["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]
    tags                        = { service = "example" }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cpu"].threshold == 90 && aws_cloudwatch_metric_alarm.this["connections"].threshold == 50 && aws_cloudwatch_metric_alarm.this["cpu"].period == 60 && aws_cloudwatch_metric_alarm.this["cpu"].evaluation_periods == 5
    error_message = "Limites e períodos dos alarmes devem ser repassados."
  }

  assert {
    condition     = alltrue([for alarm in values(aws_cloudwatch_metric_alarm.this) : alarm.alarm_actions == toset(["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]) && alarm.ok_actions == toset(["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"])])
    error_message = "As ações devem ir para todos os alarmes."
  }

  assert {
    condition = alltrue([
      aws_db_instance.this.tags == tomap({ service = "example" }),
      aws_db_parameter_group.this.tags == tomap({ service = "example" }),
      aws_db_subnet_group.this.tags == tomap({ service = "example" }),
      aws_security_group.this.tags["service"] == "example",
      aws_cloudwatch_metric_alarm.this["cpu"].tags == tomap({ service = "example" }),
    ])
    error_message = "As tags devem ir para todos os recursos que aceitam tags."
  }
}
