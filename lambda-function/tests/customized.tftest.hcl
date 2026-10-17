mock_provider "aws" {
  override_during = plan
}

variables {
  name                     = "example-fn"
  filename                 = "function.zip"
  source_code_hash         = "bW9jay1oYXNo"
  handler                  = "index.handler"
  role_path                = "/example/test/"
  permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
}

run "custom_values" {
  command = plan

  variables {
    role_name                      = "example-fn-execution"
    architectures                  = ["x86_64"]
    memory_size                    = 512
    timeout                        = 30
    reserved_concurrent_executions = 2
    environment_variables          = { POWERTOOLS_SERVICE_NAME = "example" }
    tracing_mode                   = "PassThrough"
    log_format                     = "Text"
    log_retention_in_days          = 14
    log_group_kms_key_arn          = "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example"
    additional_policies            = { queue-access = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sqs:SendMessage", Resource = "arn:aws:sqs:us-east-1:${format("%012d", 0)}:example-queue" }] }) }
    error_alarm_period             = 60
    error_alarm_evaluation_periods = 3
    error_alarm_threshold          = 5
    alarm_actions                  = ["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]
    ok_actions                     = ["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]
    tags                           = { service = "example" }
  }

  assert {
    condition     = aws_iam_role.this.name == "example-fn-execution"
    error_message = "role_name deve sobrescrever o nome da role."
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables == tomap({ POWERTOOLS_SERVICE_NAME = "example" })
    error_message = "As variáveis de ambiente devem ser repassadas."
  }

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["x86_64"]) && aws_lambda_function.this.reserved_concurrent_executions == 2
    error_message = "Arquitetura e concorrência devem ser repassadas."
  }

  assert {
    condition     = aws_lambda_function.this.tracing_config[0].mode == "PassThrough" && aws_lambda_function.this.logging_config[0].log_format == "Text"
    error_message = "Tracing e formato de log devem ser repassados."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 14 && aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example"
    error_message = "Retenção e chave do log group devem ser repassadas."
  }

  assert {
    condition     = keys(aws_iam_role_policy.additional) == ["queue-access"] && aws_iam_role_policy.additional["queue-access"].name == "queue-access" && jsondecode(aws_iam_role_policy.additional["queue-access"].policy).Statement[0].Action == "sqs:SendMessage"
    error_message = "Cada item de additional_policies deve virar uma política inline com o nome da chave."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.errors.period == 60 && aws_cloudwatch_metric_alarm.errors.evaluation_periods == 3 && aws_cloudwatch_metric_alarm.errors.threshold == 5
    error_message = "Parâmetros do alarme devem ser repassados."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.errors.alarm_actions == toset(["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]) && aws_cloudwatch_metric_alarm.errors.ok_actions == toset(["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"])
    error_message = "Ações do alarme devem ser repassadas."
  }

  assert {
    condition = alltrue([
      aws_lambda_function.this.tags == tomap({ service = "example" }),
      aws_iam_role.this.tags == tomap({ service = "example" }),
      aws_cloudwatch_log_group.this.tags == tomap({ service = "example" }),
      aws_cloudwatch_metric_alarm.errors.tags == tomap({ service = "example" }),
    ])
    error_message = "As tags devem ir para todos os recursos que aceitam tags."
  }
}
