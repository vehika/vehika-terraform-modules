mock_provider "aws" {
  override_during = plan

  override_resource {
    target = aws_cloudwatch_log_group.this
    values = {
      arn = "arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:/aws/lambda/example-fn"
    }
  }
}

variables {
  name                     = "example-fn"
  filename                 = "function.zip"
  source_code_hash         = "bW9jay1oYXNo"
  handler                  = "index.handler"
  role_path                = "/example/test/"
  permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
}

run "function_defaults" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "example-fn"
    error_message = "O nome da função deve vir de var.name."
  }

  assert {
    condition     = aws_lambda_function.this.runtime == "nodejs24.x"
    error_message = "O runtime padrão deve ser nodejs24.x."
  }

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["arm64"])
    error_message = "A arquitetura padrão deve ser arm64."
  }

  assert {
    condition     = aws_lambda_function.this.tracing_config[0].mode == "Active"
    error_message = "O tracing padrão deve ser Active."
  }

  assert {
    condition     = aws_lambda_function.this.memory_size == 256 && aws_lambda_function.this.timeout == 10
    error_message = "Memória e timeout padrão devem ser 256 MB e 10 s."
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == -1
    error_message = "Por padrão não deve haver concorrência reservada."
  }

  assert {
    condition     = length(aws_lambda_function.this.environment) == 0
    error_message = "Sem variáveis de ambiente, o bloco environment não deve existir."
  }

  assert {
    condition     = aws_lambda_function.this.logging_config[0].log_format == "JSON"
    error_message = "O formato de log padrão deve ser JSON."
  }

  assert {
    condition     = aws_lambda_function.this.logging_config[0].log_group == "/aws/lambda/example-fn"
    error_message = "A função deve escrever no log group do módulo."
  }

  assert {
    condition     = aws_lambda_function.this.filename == "function.zip" && aws_lambda_function.this.source_code_hash == "bW9jay1oYXNo"
    error_message = "O código deve ir por upload direto do zip, com filename e source_code_hash."
  }

  assert {
    condition     = aws_lambda_function.this.s3_bucket == null
    error_message = "O módulo não deve usar zip no S3."
  }
}

run "log_group" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/example-fn"
    error_message = "O log group deve ser /aws/lambda/<name>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "A retenção padrão deve ser 30 dias."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == null
    error_message = "Sem chave informada, o log group não deve usar CMK."
  }
}

run "execution_role" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "example-fn"
    error_message = "Sem role_name, a role deve usar o nome da função."
  }

  assert {
    condition     = aws_iam_role.this.path == "/example/test/"
    error_message = "A role deve usar o caminho informado."
  }

  assert {
    condition     = aws_iam_role.this.permissions_boundary == var.permissions_boundary_arn
    error_message = "A role deve carregar o permissions boundary informado."
  }

  assert {
    condition = jsondecode(aws_iam_role.this.assume_role_policy).Statement == [
      {
        Sid       = "LambdaAssumeRole"
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "lambda.amazonaws.com" }
      },
    ]
    error_message = "A confiança deve aceitar só lambda.amazonaws.com."
  }

  assert {
    condition     = length(aws_iam_role_policy.additional) == 0
    error_message = "Sem additional_policies, nenhuma política adicional deve existir."
  }
}

run "base_policy" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.base.policy).Statement) == 2
    error_message = "A política base deve ter só os statements de logs e X-Ray."
  }

  assert {
    condition = [
      for statement in jsondecode(aws_iam_role_policy.base.policy).Statement : statement
      if statement.Sid == "WriteOwnLogGroup"
      ][0] == {
      Sid      = "WriteOwnLogGroup"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = ["arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:/aws/lambda/example-fn:*"]
    }
    error_message = "Logs: só CreateLogStream e PutLogEvents, só nos streams do log group do módulo."
  }

  assert {
    condition = [
      for statement in jsondecode(aws_iam_role_policy.base.policy).Statement : statement
      if statement.Sid == "SendTraces"
      ][0] == {
      Sid      = "SendTraces"
      Effect   = "Allow"
      Action   = ["xray:PutTelemetryRecords", "xray:PutTraceSegments"]
      Resource = ["*"]
    }
    error_message = "X-Ray: só PutTraceSegments e PutTelemetryRecords."
  }

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(aws_iam_role_policy.base.policy).Statement : [
        for action in statement.Action : !strcontains(action, "*")
      ]
    ]))
    error_message = "A política base não deve ter curinga em ações."
  }
}

run "error_alarm" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.errors.alarm_name == "example-fn-errors"
    error_message = "O alarme deve se chamar <name>-errors."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.errors.namespace == "AWS/Lambda" && aws_cloudwatch_metric_alarm.errors.metric_name == "Errors"
    error_message = "O alarme deve observar AWS/Lambda Errors."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.errors.dimensions == tomap({ FunctionName = "example-fn" })
    error_message = "O alarme deve filtrar pela dimensão FunctionName da função."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.errors.statistic == "Sum" && aws_cloudwatch_metric_alarm.errors.period == 300 && aws_cloudwatch_metric_alarm.errors.evaluation_periods == 1
    error_message = "Padrão do alarme: Sum em 1 período de 300 s."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.errors.threshold == 1 && aws_cloudwatch_metric_alarm.errors.comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "Padrão do alarme: dispara com 1 erro ou mais."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.errors.treat_missing_data == "notBreaching"
    error_message = "Ausência de dados não deve disparar o alarme."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.errors.alarm_actions) == 0 && length(aws_cloudwatch_metric_alarm.errors.ok_actions) == 0
    error_message = "Por padrão o alarme não tem ações."
  }
}
