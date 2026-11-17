mock_provider "aws" {
  override_during = plan

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = format("%012d", 0)
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.flow_logs
    values = {
      arn = "arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:/vpc/example-net/flow-logs"
    }
  }
}

variables {
  name               = "example-net"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

run "flow_logs_to_cloudwatch" {
  command = plan

  variables {
    flow_logs_enabled        = true
    role_path                = "/example/test/"
    permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs[0].name == "/vpc/example-net/flow-logs" && aws_cloudwatch_log_group.flow_logs[0].retention_in_days == 30
    error_message = "O log group padrão deve ser /vpc/<name>/flow-logs com 30 dias de retenção."
  }

  assert {
    condition     = aws_iam_role.flow_logs[0].name == "example-net-flow-logs" && aws_iam_role.flow_logs[0].path == "/example/test/" && aws_iam_role.flow_logs[0].permissions_boundary == var.permissions_boundary_arn
    error_message = "A role dos flow logs deve ter nome, caminho e boundary."
  }

  assert {
    condition = jsondecode(aws_iam_role.flow_logs[0].assume_role_policy).Statement[0] == {
      Sid       = "FlowLogsAssumeRole"
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Condition = { StringEquals = { "aws:SourceAccount" = format("%012d", 0) } }
    }
    error_message = "A confiança deve aceitar só vpc-flow-logs.amazonaws.com da própria conta."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.flow_logs[0].policy).Statement[0].Resource == ["arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:/vpc/example-net/flow-logs:*"]
    error_message = "A role só deve escrever nos streams do próprio log group."
  }

  assert {
    condition     = aws_flow_log.this[0].log_destination_type == "cloud-watch-logs" && aws_flow_log.this[0].traffic_type == "ALL" && aws_flow_log.this[0].max_aggregation_interval == 600
    error_message = "Os flow logs devem ir para o CloudWatch Logs com ALL e 600 s."
  }
}

run "flow_logs_to_s3" {
  command = plan

  variables {
    flow_logs_enabled          = true
    flow_logs_destination_type = "s3"
    flow_logs_s3_bucket_arn    = "arn:aws:s3:::example-flow-logs/vpc"
    flow_logs_traffic_type     = "REJECT"
  }

  assert {
    condition     = aws_flow_log.this[0].log_destination == "arn:aws:s3:::example-flow-logs/vpc" && aws_flow_log.this[0].iam_role_arn == null
    error_message = "No destino s3 os flow logs vão para o bucket, sem role."
  }

  assert {
    condition     = length(aws_iam_role.flow_logs) == 0 && length(aws_cloudwatch_log_group.flow_logs) == 0
    error_message = "No destino s3 não deve haver role nem log group."
  }
}
