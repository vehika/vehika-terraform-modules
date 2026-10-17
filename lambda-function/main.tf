locals {
  role_name      = coalesce(var.role_name, var.name)
  log_group_name = "/aws/lambda/${var.name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LambdaAssumeRole"
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "lambda.amazonaws.com" }
      },
    ]
  })

  # As ações do X-Ray não aceitam escopo por recurso.
  base_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteOwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.this.arn}:*"]
      },
      {
        Sid      = "SendTraces"
        Effect   = "Allow"
        Action   = ["xray:PutTelemetryRecords", "xray:PutTraceSegments"]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_group_kms_key_arn
  tags              = var.tags
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  path                 = var.role_path
  description          = "Role de execução da função Lambda ${var.name}."
  assume_role_policy   = local.assume_role_policy
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy" "base" {
  name   = "base"
  role   = aws_iam_role.this.id
  policy = local.base_policy
}

resource "aws_iam_role_policy" "additional" {
  for_each = var.additional_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

resource "aws_lambda_function" "this" {
  function_name                  = var.name
  description                    = var.description
  role                           = aws_iam_role.this.arn
  filename                       = var.filename
  source_code_hash               = var.source_code_hash
  handler                        = var.handler
  runtime                        = var.runtime
  architectures                  = var.architectures
  memory_size                    = var.memory_size
  timeout                        = var.timeout
  reserved_concurrent_executions = var.reserved_concurrent_executions
  tags                           = var.tags

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [var.environment_variables] : []

    content {
      variables = environment.value
    }
  }

  tracing_config {
    mode = var.tracing_mode
  }

  logging_config {
    log_format = var.log_format
    log_group  = aws_cloudwatch_log_group.this.name
  }

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy.base,
    aws_iam_role_policy.additional,
  ]
}

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.name}-errors"
  alarm_description   = "Erros da função Lambda ${var.name}."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = var.error_alarm_period
  evaluation_periods  = var.error_alarm_evaluation_periods
  threshold           = var.error_alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = var.tags

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }
}
