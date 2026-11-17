mock_provider "aws" {}

variables {
  identifier = "example-db"
  vpc_id     = "vpc-0example"
  subnet_ids = ["subnet-0example1", "subnet-0example2"]
}

run "rejects_invalid_identifier" {
  command = plan

  variables {
    identifier = "Example_DB"
  }

  expect_failures = [var.identifier]
}

run "rejects_zero_backup_retention" {
  command = plan

  variables {
    backup_retention_period = 0
  }

  expect_failures = [var.backup_retention_period]
}

run "rejects_max_storage_below_allocated" {
  command = plan

  variables {
    allocated_storage     = 50
    max_allocated_storage = 40
  }

  expect_failures = [var.max_allocated_storage]
}

run "rejects_overriding_force_ssl" {
  command = plan

  variables {
    parameters = [{ name = "rds.force_ssl", value = "0" }]
  }

  expect_failures = [var.parameters]
}

run "rejects_duplicated_parameter" {
  command = plan

  variables {
    parameters = [{ name = "work_mem", value = "4096" }, { name = "work_mem", value = "8192" }]
  }

  expect_failures = [var.parameters]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0example1"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_replication_without_kms" {
  command = plan

  variables {
    backup_replication_enabled = true
    backup_replication_region  = "us-east-2"
  }

  expect_failures = [var.backup_replication_kms_key_arn]
}

run "rejects_replication_without_region" {
  command = plan

  variables {
    backup_replication_enabled     = true
    backup_replication_kms_key_arn = "arn:aws:kms:us-east-2:${format("%012d", 0)}:key/example-replica"
  }

  expect_failures = [var.backup_replication_region]
}

run "rejects_replication_kms_from_other_region" {
  command = plan

  variables {
    backup_replication_enabled     = true
    backup_replication_region      = "us-east-2"
    backup_replication_kms_key_arn = "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-storage"
  }

  expect_failures = [var.backup_replication_kms_key_arn]
}

run "rejects_invalid_kms_key" {
  command = plan

  variables {
    kms_key_arn = "alias/example"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_invalid_log_export" {
  command = plan

  variables {
    enabled_cloudwatch_logs_exports = ["audit"]
  }

  expect_failures = [var.enabled_cloudwatch_logs_exports]
}

run "rejects_reserved_master_username" {
  command = plan

  variables {
    master_username = "rdsadmin"
  }

  expect_failures = [var.master_username]
}

run "rejects_invalid_engine_version" {
  command = plan

  variables {
    engine_version = "latest"
  }

  expect_failures = [var.engine_version]
}

run "rejects_invalid_backup_window" {
  command = plan

  variables {
    backup_window = "25:00-25:30"
  }

  expect_failures = [var.backup_window]
}

run "rejects_invalid_allowed_security_group_key" {
  command = plan

  variables {
    allowed_security_groups = { "chave inválida" = "sg-0example" }
  }

  expect_failures = [var.allowed_security_groups]
}
