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
      arn = "arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:/ecs/example-worker"
    }
  }
}

variables {
  name                     = "example-worker"
  cluster_arn              = "arn:aws:ecs:us-east-1:${format("%012d", 0)}:cluster/example-cluster"
  vpc_id                   = "vpc-0example"
  subnet_ids               = ["subnet-0example1", "subnet-0example2"]
  container_image          = "public.ecr.aws/example/app:1.0.0"
  role_path                = "/example/test/"
  permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
}

run "task_definition_defaults" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this.family == "example-worker" && aws_ecs_task_definition.this.requires_compatibilities == toset(["FARGATE"]) && aws_ecs_task_definition.this.network_mode == "awsvpc"
    error_message = "A task definition deve ser Fargate, awsvpc, com a família igual ao nome."
  }

  assert {
    condition     = aws_ecs_task_definition.this.runtime_platform[0].cpu_architecture == "ARM64" && aws_ecs_task_definition.this.runtime_platform[0].operating_system_family == "LINUX"
    error_message = "A arquitetura padrão deve ser ARM64 em Linux."
  }

  assert {
    condition     = aws_ecs_task_definition.this.cpu == "256" && aws_ecs_task_definition.this.memory == "512"
    error_message = "O padrão deve ser 0,25 vCPU e 512 MiB."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].name == "app" && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].image == "public.ecr.aws/example/app:1.0.0" && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].essential
    error_message = "O contêiner padrão deve se chamar app e usar a imagem informada."
  }

  assert {
    condition     = !can(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].portMappings) && !can(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets) && !can(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].environment)
    error_message = "Sem porta, segredos ou variáveis, os campos não devem existir (evita diff perpétuo)."
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration == {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/example-worker"
        awslogs-region        = "us-east-1"
        awslogs-stream-prefix = "app"
      }
    }
    error_message = "O contêiner deve escrever no log group do módulo pelo awslogs."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].linuxParameters.initProcessEnabled && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].stopTimeout == 30
    error_message = "initProcessEnabled e stopTimeout de 30 s devem vir por padrão."
  }

  assert {
    condition     = !can(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].command) && !can(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck)
    error_message = "Sem command e health_check, os campos não devem existir."
  }
}

run "service_defaults" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.name == "example-worker" && aws_ecs_service.this.cluster == var.cluster_arn && aws_ecs_service.this.desired_count == 1
    error_message = "O serviço deve usar o nome, o cluster e 1 tarefa."
  }

  assert {
    condition     = length(aws_ecs_service.this.capacity_provider_strategy) == 1 && one(aws_ecs_service.this.capacity_provider_strategy).capacity_provider == "FARGATE" && one(aws_ecs_service.this.capacity_provider_strategy).weight == 1
    error_message = "O capacity provider padrão deve ser FARGATE."
  }

  assert {
    condition     = aws_ecs_service.this.deployment_circuit_breaker[0].enable && aws_ecs_service.this.deployment_circuit_breaker[0].rollback
    error_message = "O circuit breaker com rollback deve estar ligado."
  }

  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip == false && aws_ecs_service.this.network_configuration[0].subnets == toset(["subnet-0example1", "subnet-0example2"])
    error_message = "Sem pedido explícito, as tarefas não recebem IP público."
  }

  assert {
    condition     = length(aws_ecs_service.this.load_balancer) == 0 && aws_ecs_service.this.health_check_grace_period_seconds == null
    error_message = "Sem target group, o serviço não deve se registrar em load balancer."
  }

  assert {
    condition     = aws_ecs_service.this.enable_execute_command == false && aws_ecs_service.this.propagate_tags == "SERVICE"
    error_message = "ECS Exec desligado e tags propagadas do serviço por padrão."
  }

  assert {
    condition     = aws_ecs_service.this.availability_zone_rebalancing == "ENABLED" && aws_ecs_service.this.deployment_minimum_healthy_percent == 100 && aws_ecs_service.this.deployment_maximum_percent == 200
    error_message = "O padrão deve manter o rebalanceamento entre zonas ENABLED com deploy 100/200, como na v0.1.1."
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 0 && length(aws_appautoscaling_policy.cpu) == 0
    error_message = "Sem autoscaling_max_capacity, não há autoscaling."
  }
}

run "roles" {
  command = plan

  assert {
    condition     = aws_iam_role.execution.name == "example-worker-execution" && aws_iam_role.task.name == "example-worker-task"
    error_message = "As roles devem se chamar <name>-execution e <name>-task."
  }

  assert {
    condition     = aws_iam_role.execution.permissions_boundary == var.permissions_boundary_arn && aws_iam_role.task.permissions_boundary == var.permissions_boundary_arn
    error_message = "As duas roles devem carregar o permissions boundary."
  }

  assert {
    condition     = aws_iam_role.execution.path == "/example/test/" && aws_iam_role.task.path == "/example/test/"
    error_message = "As duas roles devem usar o caminho informado."
  }

  assert {
    condition     = jsondecode(aws_iam_role.execution.assume_role_policy).Statement[0].Principal == { Service = "ecs-tasks.amazonaws.com" }
    error_message = "A role de execução deve confiar só em ecs-tasks.amazonaws.com."
  }

  assert {
    condition = jsondecode(aws_iam_role.task.assume_role_policy).Statement[0].Condition == {
      StringEquals = { "aws:SourceAccount" = format("%012d", 0) }
      ArnLike      = { "aws:SourceArn" = "arn:aws:ecs:us-east-1:${format("%012d", 0)}:*" }
    }
    error_message = "A role da tarefa deve conferir a conta e a origem do ECS."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.execution.policy).Statement == [
      {
        Sid      = "WriteOwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:/ecs/example-worker:*"]
      },
    ]
    error_message = "Sem ECR, segredos ou chaves, a role de execução só escreve no próprio log group."
  }

  assert {
    condition     = length(aws_iam_role_policy.task) == 0 && length(aws_iam_role_policy.ecs_exec) == 0
    error_message = "A role da tarefa deve nascer sem permissões."
  }
}

run "security_group" {
  command = plan

  assert {
    condition     = aws_security_group.this.name_prefix == "example-worker-" && aws_security_group.this.vpc_id == "vpc-0example"
    error_message = "O security group deve ser criado na VPC informada."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.allowed) == 0
    error_message = "Sem allowed_security_groups, nenhuma entrada deve existir."
  }

  assert {
    condition     = keys(aws_vpc_security_group_egress_rule.this) == ["https"] && aws_vpc_security_group_egress_rule.this["https"].from_port == 443 && aws_vpc_security_group_egress_rule.this["https"].to_port == 443 && aws_vpc_security_group_egress_rule.this["https"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "A saída padrão deve ser só HTTPS para a internet."
  }
}

run "logs_and_alarms" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/ecs/example-worker" && aws_cloudwatch_log_group.this.retention_in_days == 30 && aws_cloudwatch_log_group.this.kms_key_id == null
    error_message = "Log group padrão: /ecs/<name>, 30 dias, sem CMK."
  }

  assert {
    condition     = keys(aws_cloudwatch_metric_alarm.this) == ["cpu", "memory"] && aws_cloudwatch_metric_alarm.this["cpu"].alarm_name == "example-worker-cpu" && aws_cloudwatch_metric_alarm.this["memory"].metric_name == "MemoryUtilization"
    error_message = "Devem existir os alarmes <name>-cpu e <name>-memory."
  }

  assert {
    condition     = alltrue([for alarm in values(aws_cloudwatch_metric_alarm.this) : alarm.namespace == "AWS/ECS" && alarm.threshold == 85 && alarm.dimensions == tomap({ ClusterName = "example-cluster", ServiceName = "example-worker" })])
    error_message = "Os alarmes devem observar AWS/ECS do serviço, com limite de 85%."
  }
}

run "worker_zero_to_one_hundred_with_rebalancing_disabled" {
  command = plan

  variables {
    deployment_minimum_healthy_percent = 0
    deployment_maximum_percent         = 100
    availability_zone_rebalancing      = "DISABLED"
  }

  assert {
    condition     = aws_ecs_service.this.availability_zone_rebalancing == "DISABLED" && aws_ecs_service.this.deployment_minimum_healthy_percent == 0 && aws_ecs_service.this.deployment_maximum_percent == 100
    error_message = "O worker 0/100 com DISABLED deve passar e repassar os três valores ao serviço."
  }
}

run "rebalancing_disabled_with_default_deployment" {
  command = plan

  variables {
    availability_zone_rebalancing = "DISABLED"
  }

  assert {
    condition     = aws_ecs_service.this.availability_zone_rebalancing == "DISABLED" && aws_ecs_service.this.deployment_maximum_percent == 200
    error_message = "DISABLED também deve ser aceito com o deploy padrão 100/200."
  }
}

run "task_definition_skip_destroy_default" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this.skip_destroy == true
    error_message = "Por padrão, a revisão antiga da task definition deve continuar ACTIVE (skip_destroy = true) para o rollback do circuit breaker."
  }
}

run "task_definition_skip_destroy_disabled" {
  command = plan

  variables {
    task_definition_skip_destroy = false
  }

  assert {
    condition     = aws_ecs_task_definition.this.skip_destroy == false
    error_message = "Com task_definition_skip_destroy = false, a substituição deve desregistrar a revisão antiga, como na v0.1.2."
  }
}

run "task_definition_skip_destroy_null_uses_default" {
  command = plan

  variables {
    task_definition_skip_destroy = null
  }

  assert {
    condition     = aws_ecs_task_definition.this.skip_destroy == true
    error_message = "null não pode cair no padrão false do provider: a variável não é anulável e deve usar true."
  }
}
