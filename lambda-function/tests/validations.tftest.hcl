mock_provider "aws" {}

variables {
  name                     = "example-fn"
  filename                 = "function.zip"
  source_code_hash         = "bW9jay1oYXNo"
  handler                  = "index.handler"
  role_path                = "/example/test/"
  permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "nome com espaço"
  }

  expect_failures = [var.name]
}

run "accepts_defaults_without_overrides" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "example-fn" && aws_iam_role.this.permissions_boundary == var.permissions_boundary_arn
    error_message = "O plan com os padrões deve passar sem override_resource."
  }
}

run "rejects_name_longer_than_64" {
  command = plan

  variables {
    name = join("", [for index in range(65) : "a"])
  }

  expect_failures = [var.name]
}

run "accepts_govcloud_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws-us-gov:iam::${format("%012d", 0)}:policy/x"
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws-us-gov:iam::${format("%012d", 0)}:policy/x"
    error_message = "Um boundary de outra partição deve ser aceito."
  }
}

run "accepts_aws_managed_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::aws:policy/x"
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == "arn:aws:iam::aws:policy/x"
    error_message = "Uma política gerenciada pela AWS deve ser aceita como boundary."
  }
}

run "rejects_invalid_architecture" {
  command = plan

  variables {
    architectures = ["arm64", "x86_64"]
  }

  expect_failures = [var.architectures]
}

run "rejects_invalid_memory_size" {
  command = plan

  variables {
    memory_size = 64
  }

  expect_failures = [var.memory_size]
}

run "rejects_invalid_timeout" {
  command = plan

  variables {
    timeout = 901
  }

  expect_failures = [var.timeout]
}

run "rejects_invalid_reserved_concurrency" {
  command = plan

  variables {
    reserved_concurrent_executions = -2
  }

  expect_failures = [var.reserved_concurrent_executions]
}

run "rejects_invalid_tracing_mode" {
  command = plan

  variables {
    tracing_mode = "Disabled"
  }

  expect_failures = [var.tracing_mode]
}

run "rejects_invalid_log_format" {
  command = plan

  variables {
    log_format = "XML"
  }

  expect_failures = [var.log_format]
}

run "rejects_invalid_retention" {
  command = plan

  variables {
    log_retention_in_days = 31
  }

  expect_failures = [var.log_retention_in_days]
}

run "rejects_invalid_role_name" {
  command = plan

  variables {
    role_name = "nome/invalido"
  }

  expect_failures = [var.role_name]
}

run "rejects_role_path_without_trailing_slash" {
  command = plan

  variables {
    role_path = "/example/test"
  }

  expect_failures = [var.role_path]
}

run "rejects_empty_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = ""
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_role_arn_as_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:role/example-role"
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_invalid_additional_policy_document" {
  command = plan

  variables {
    additional_policies = { extra = "{ isso não é json" }
  }

  expect_failures = [var.additional_policies]
}

run "rejects_invalid_additional_policy_name" {
  command = plan

  variables {
    additional_policies = { "nome inválido" = jsonencode({ Version = "2012-10-17", Statement = [] }) }
  }

  expect_failures = [var.additional_policies]
}

run "rejects_additional_policy_named_base" {
  command = plan

  variables {
    additional_policies = { base = jsonencode({ Version = "2012-10-17", Statement = [] }) }
  }

  expect_failures = [var.additional_policies]
}

run "rejects_invalid_kms_key_arn" {
  command = plan

  variables {
    log_group_kms_key_arn = "alias/example"
  }

  expect_failures = [var.log_group_kms_key_arn]
}

run "rejects_invalid_alarm_period" {
  command = plan

  variables {
    error_alarm_period = 90
  }

  expect_failures = [var.error_alarm_period]
}

run "rejects_invalid_alarm_evaluation_periods" {
  command = plan

  variables {
    error_alarm_evaluation_periods = 0
  }

  expect_failures = [var.error_alarm_evaluation_periods]
}

run "rejects_invalid_alarm_threshold" {
  command = plan

  variables {
    error_alarm_threshold = 0
  }

  expect_failures = [var.error_alarm_threshold]
}
