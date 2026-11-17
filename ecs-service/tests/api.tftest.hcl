mock_provider "aws" {
  override_during = plan

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = format("%012d", 0)
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.this
    values = {
      arn = "arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:/example/test/api"
    }
  }
}

variables {
  name                     = "example-api"
  cluster_arn              = "arn:aws:ecs:us-east-1:${format("%012d", 0)}:cluster/example-cluster"
  vpc_id                   = "vpc-0example"
  subnet_ids               = ["subnet-0example1", "subnet-0example2"]
  container_image          = "${format("%012d", 0)}.dkr.ecr.us-east-1.amazonaws.com/example-app@sha256:0000"
  role_path                = "/example/test/"
  permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
}

run "api_behind_alb" {
  command = plan

  variables {
    container_port           = 3000
    target_group_arn         = "arn:aws:elasticloadbalancing:us-east-1:${format("%012d", 0)}:targetgroup/example-api/0000000000000000"
    allowed_security_groups  = { alb = "sg-0examplealb" }
    assign_public_ip         = true
    desired_count            = 2
    autoscaling_max_capacity = 4
    log_group_name           = "/example/test/api"
    log_retention_in_days    = 14
    log_group_kms_key_arn    = "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-logs"
    egress_rules = {
      https    = { description = "HTTPS", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
      postgres = { description = "PostgreSQL", ip_protocol = "tcp", from_port = 5432, to_port = 5432, referenced_security_group_id = "sg-0exampledb" }
    }
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].portMappings == [{ containerPort = 3000, hostPort = 3000, protocol = "tcp" }]
    error_message = "A porta do contêiner deve ser mapeada."
  }

  assert {
    condition     = one(aws_ecs_service.this.load_balancer).target_group_arn == var.target_group_arn && one(aws_ecs_service.this.load_balancer).container_name == "app" && one(aws_ecs_service.this.load_balancer).container_port == 3000
    error_message = "O serviço deve se registrar no target group com o contêiner e a porta."
  }

  assert {
    condition     = aws_ecs_service.this.health_check_grace_period_seconds == 60
    error_message = "Com target group, o grace period padrão é 60 s."
  }

  assert {
    condition     = keys(aws_vpc_security_group_ingress_rule.allowed) == ["alb"] && aws_vpc_security_group_ingress_rule.allowed["alb"].referenced_security_group_id == "sg-0examplealb" && aws_vpc_security_group_ingress_rule.allowed["alb"].from_port == 3000 && aws_vpc_security_group_ingress_rule.allowed["alb"].to_port == 3000 && aws_vpc_security_group_ingress_rule.allowed["alb"].cidr_ipv4 == null
    error_message = "A entrada deve aceitar só o security group do ALB, só na porta do contêiner."
  }

  assert {
    condition     = keys(aws_vpc_security_group_egress_rule.this) == ["https", "postgres"] && aws_vpc_security_group_egress_rule.this["postgres"].referenced_security_group_id == "sg-0exampledb"
    error_message = "As regras de saída informadas devem ser criadas."
  }

  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip
    error_message = "assign_public_ip deve ser repassado."
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].min_capacity == 2 && aws_appautoscaling_target.this[0].max_capacity == 4 && aws_appautoscaling_target.this[0].resource_id == "service/example-cluster/example-api"
    error_message = "O autoscaling deve ir de desired_count a autoscaling_max_capacity no serviço do cluster."
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu[0].policy_type == "TargetTrackingScaling" && aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration[0].target_value == 70 && aws_appautoscaling_policy.cpu[0].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ECSServiceAverageCPUUtilization"
    error_message = "O autoscaling deve seguir a CPU média com alvo de 70%."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/example/test/api" && aws_cloudwatch_log_group.this.retention_in_days == 14 && aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-logs"
    error_message = "Nome, retenção e CMK do log group devem ser repassados."
  }
}

run "secrets_without_values" {
  command = plan

  variables {
    environment = { NODE_ENV = "production", PORT = "3000" }
    secrets = {
      DATABASE_URL = "/example/test/api/database-url"
      API_TOKEN    = "arn:aws:ssm:us-east-1:${format("%012d", 0)}:parameter/example/test/api/token"
      DB_PASSWORD  = "arn:aws:secretsmanager:us-east-1:${format("%012d", 0)}:secret:example-db-AbCdEf:password::"
    }
    secrets_kms_key_arns = ["arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-ssm"]
    ecr_repository_arns  = ["arn:aws:ecr:us-east-1:${format("%012d", 0)}:repository/example-app"]
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets == [
      { name = "API_TOKEN", valueFrom = "arn:aws:ssm:us-east-1:${format("%012d", 0)}:parameter/example/test/api/token" },
      { name = "DATABASE_URL", valueFrom = "arn:aws:ssm:us-east-1:${format("%012d", 0)}:parameter/example/test/api/database-url" },
      { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:us-east-1:${format("%012d", 0)}:secret:example-db-AbCdEf:password::" },
    ]
    error_message = "Segredos devem ir como valueFrom (nome do SSM vira ARN), nunca como valor."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment == [{ name = "NODE_ENV", value = "production" }, { name = "PORT", value = "3000" }]
    error_message = "As variáveis de ambiente devem ir ordenadas por nome."
  }

  assert {
    condition = [for statement in jsondecode(aws_iam_role_policy.execution.policy).Statement : statement.Resource if statement.Sid == "ReadSsmParameters"][0] == [
      "arn:aws:ssm:us-east-1:${format("%012d", 0)}:parameter/example/test/api/database-url",
      "arn:aws:ssm:us-east-1:${format("%012d", 0)}:parameter/example/test/api/token",
    ]
    error_message = "A role de execução deve ler só os parâmetros SSM informados."
  }

  assert {
    condition     = [for statement in jsondecode(aws_iam_role_policy.execution.policy).Statement : statement.Resource if statement.Sid == "ReadSecrets"][0] == ["arn:aws:secretsmanager:us-east-1:${format("%012d", 0)}:secret:example-db-AbCdEf"]
    error_message = "A role de execução deve ler só o segredo informado, sem o sufixo da chave JSON."
  }

  assert {
    condition     = [for statement in jsondecode(aws_iam_role_policy.execution.policy).Statement : statement.Resource if statement.Sid == "DecryptSecrets"][0] == ["arn:aws:kms:us-east-1:${format("%012d", 0)}:key/example-ssm"]
    error_message = "kms:Decrypt só nas chaves informadas."
  }

  assert {
    condition     = [for statement in jsondecode(aws_iam_role_policy.execution.policy).Statement : statement.Resource if statement.Sid == "PullImages"][0] == ["arn:aws:ecr:us-east-1:${format("%012d", 0)}:repository/example-app"]
    error_message = "O pull de imagens deve ficar restrito aos repositórios informados."
  }

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(aws_iam_role_policy.execution.policy).Statement : [
        for action in statement.Action : !strcontains(action, "*")
      ]
    ]))
    error_message = "A política de execução não deve ter curinga em ações."
  }

  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_role_policy.execution.policy).Statement : statement.Resource != ["*"] if statement.Sid != "GetEcrToken"])
    error_message = "Só ecr:GetAuthorizationToken pode usar Resource *."
  }
}

run "worker_on_spot" {
  command = plan

  variables {
    capacity_provider_strategy = [{ capacity_provider = "FARGATE_SPOT" }]
    command                    = ["node", "dist/worker.js"]
    stop_timeout               = 120
  }

  assert {
    condition     = length(aws_ecs_service.this.capacity_provider_strategy) == 1 && one(aws_ecs_service.this.capacity_provider_strategy).capacity_provider == "FARGATE_SPOT"
    error_message = "O worker deve rodar em FARGATE_SPOT."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].command == ["node", "dist/worker.js"] && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].stopTimeout == 120
    error_message = "command e stop_timeout devem ser repassados."
  }
}

run "mixed_capacity_and_x86" {
  command = plan

  variables {
    capacity_provider_strategy = [{ capacity_provider = "FARGATE", base = 1, weight = 1 }, { capacity_provider = "FARGATE_SPOT", weight = 3 }]
    cpu_architecture           = "X86_64"
    cpu                        = 512
    memory                     = 1024
  }

  assert {
    condition     = length(aws_ecs_service.this.capacity_provider_strategy) == 2
    error_message = "A estratégia mista deve ter os dois capacity providers."
  }

  assert {
    condition     = aws_ecs_task_definition.this.runtime_platform[0].cpu_architecture == "X86_64" && aws_ecs_task_definition.this.cpu == "512" && aws_ecs_task_definition.this.memory == "1024"
    error_message = "Arquitetura, cpu e memória devem ser repassadas."
  }
}

run "exec_task_policies_and_health_check" {
  command = plan

  variables {
    enable_execute_command   = true
    readonly_root_filesystem = true
    task_role_policies       = { queue-access = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sqs:SendMessage", Resource = "arn:aws:sqs:us-east-1:${format("%012d", 0)}:example-queue" }] }) }
    health_check             = { command = ["CMD-SHELL", "exit 0"] }
    alarm_actions            = ["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"]
    tags                     = { service = "example" }
  }

  assert {
    condition     = aws_ecs_service.this.enable_execute_command && length(aws_iam_role_policy.ecs_exec) == 1 && jsondecode(aws_iam_role_policy.ecs_exec[0].policy).Statement[0].Action == ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
    error_message = "ECS Exec deve ligar o serviço e dar à role da tarefa só as ações ssmmessages."
  }

  assert {
    condition     = keys(aws_iam_role_policy.task) == ["queue-access"] && aws_iam_role_policy.task["queue-access"].name == "queue-access" && jsondecode(aws_iam_role_policy.task["queue-access"].policy).Statement[0].Action == "sqs:SendMessage"
    error_message = "Cada item de task_role_policies deve virar uma política inline da role da tarefa."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].readonlyRootFilesystem && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck == { command = ["CMD-SHELL", "exit 0"], interval = 30, timeout = 5, retries = 3, startPeriod = 0 }
    error_message = "readonlyRootFilesystem e healthCheck devem ser repassados."
  }

  assert {
    condition     = alltrue([for alarm in values(aws_cloudwatch_metric_alarm.this) : alarm.alarm_actions == toset(["arn:aws:sns:us-east-1:${format("%012d", 0)}:example-topic"])])
    error_message = "As ações devem ir para todos os alarmes."
  }

  assert {
    condition = alltrue([
      aws_ecs_service.this.tags == tomap({ service = "example" }),
      aws_ecs_task_definition.this.tags == tomap({ service = "example" }),
      aws_iam_role.task.tags == tomap({ service = "example" }),
      aws_iam_role.execution.tags == tomap({ service = "example" }),
      aws_cloudwatch_log_group.this.tags == tomap({ service = "example" }),
      aws_security_group.this.tags["service"] == "example",
      aws_cloudwatch_metric_alarm.this["cpu"].tags == tomap({ service = "example" }),
    ])
    error_message = "As tags devem ir para todos os recursos que aceitam tags."
  }
}
