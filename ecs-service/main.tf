data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  cluster_name        = element(split("/", var.cluster_arn), 1)
  log_group_name      = coalesce(var.log_group_name, "/ecs/${var.name}")
  task_role_name      = coalesce(var.task_role_name, "${var.name}-task")
  execution_role_name = coalesce(var.execution_role_name, "${var.name}-execution")

  # Nome de parâmetro SSM vira ARN na região e conta atuais; ARNs passam direto.
  secret_value_from = {
    for env_name, value_from in var.secrets : env_name => (
      startswith(value_from, "arn:") ? value_from : "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter/${trimprefix(value_from, "/")}"
    )
  }

  ssm_parameter_arns = sort(distinct([
    for value_from in values(local.secret_value_from) : value_from if strcontains(value_from, ":ssm:")
  ]))

  # Remove o sufixo :<chave-json>:<estágio>:<versão>; o ARN do segredo tem 7
  # partes. A validação de var.secrets exige o ARN completo (com o sufixo
  # aleatório -XXXXXX), então a política usa o ARN exato, sem curinga.
  secrets_manager_arns = sort(distinct([
    for value_from in values(local.secret_value_from) : join(":", slice(split(":", value_from), 0, 7)) if strcontains(value_from, ":secretsmanager:")
  ]))

  container_definition = merge(
    {
      name                   = var.container_name
      image                  = var.container_image
      essential              = true
      readonlyRootFilesystem = var.readonly_root_filesystem
      stopTimeout            = var.stop_timeout
      linuxParameters        = { initProcessEnabled = true }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = local.log_group_name
          awslogs-region        = local.region
          awslogs-stream-prefix = var.container_name
        }
      }
    },
    # Listas vazias ficam fora: a API não as devolve, e o diff criaria uma
    # revisão nova da task definition a cada apply.
    length(var.environment) == 0 ? {} : { environment = [for env_name in sort(keys(var.environment)) : { name = env_name, value = var.environment[env_name] }] },
    length(var.secrets) == 0 ? {} : { secrets = [for env_name in sort(keys(local.secret_value_from)) : { name = env_name, valueFrom = local.secret_value_from[env_name] }] },
    var.container_port == null ? {} : { portMappings = [{ containerPort = var.container_port, hostPort = var.container_port, protocol = "tcp" }] },
    var.command == null ? {} : { command = var.command },
    var.entry_point == null ? {} : { entryPoint = var.entry_point },
    var.health_check == null ? {} : {
      healthCheck = {
        command     = var.health_check.command
        interval    = var.health_check.interval
        timeout     = var.health_check.timeout
        retries     = var.health_check.retries
        startPeriod = var.health_check.start_period
      }
    },
  )

  # Só o ECS assume as roles. A role da tarefa também confere conta e origem.
  execution_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EcsTasksAssumeRole"
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      },
    ]
  })

  task_assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EcsTasksAssumeRole"
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:*" }
        }
      },
    ]
  })

  # ecr:GetAuthorizationToken não aceita escopo por recurso.
  execution_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "WriteOwnLogGroup"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = ["${aws_cloudwatch_log_group.this.arn}:*"]
        },
      ],
      length(var.ecr_repository_arns) == 0 ? [] : [
        {
          Sid      = "GetEcrToken"
          Effect   = "Allow"
          Action   = ["ecr:GetAuthorizationToken"]
          Resource = ["*"]
        },
        {
          Sid      = "PullImages"
          Effect   = "Allow"
          Action   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
          Resource = sort(var.ecr_repository_arns)
        },
      ],
      length(local.ssm_parameter_arns) == 0 ? [] : [
        {
          Sid      = "ReadSsmParameters"
          Effect   = "Allow"
          Action   = ["ssm:GetParameters"]
          Resource = local.ssm_parameter_arns
        },
      ],
      length(local.secrets_manager_arns) == 0 ? [] : [
        {
          Sid      = "ReadSecrets"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = local.secrets_manager_arns
        },
      ],
      length(var.secrets_kms_key_arns) == 0 ? [] : [
        {
          Sid      = "DecryptSecrets"
          Effect   = "Allow"
          Action   = ["kms:Decrypt"]
          Resource = sort(var.secrets_kms_key_arns)
        },
      ],
    )
  })

  # As ações ssmmessages não aceitam escopo por recurso.
  ecs_exec_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcsExec"
        Effect   = "Allow"
        Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
        Resource = ["*"]
      },
    ]
  })

  alarms = {
    cpu = {
      description = "CPU média do serviço ECS ${var.name} acima de ${var.cpu_alarm_threshold}%."
      metric_name = "CPUUtilization"
      threshold   = var.cpu_alarm_threshold
    }
    memory = {
      description = "Memória média do serviço ECS ${var.name} acima de ${var.memory_alarm_threshold}%."
      metric_name = "MemoryUtilization"
      threshold   = var.memory_alarm_threshold
    }
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_group_kms_key_arn
  tags              = var.tags
}

resource "aws_iam_role" "execution" {
  name                 = local.execution_role_name
  path                 = var.role_path
  description          = "Role de execucao do servico ECS ${var.name}."
  assume_role_policy   = local.execution_assume_role_policy
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy" "execution" {
  name   = "execution"
  role   = aws_iam_role.execution.id
  policy = local.execution_policy
}

resource "aws_iam_role" "task" {
  name                 = local.task_role_name
  path                 = var.role_path
  description          = "Role da tarefa do servico ECS ${var.name}."
  assume_role_policy   = local.task_assume_role_policy
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

resource "aws_iam_role_policy" "ecs_exec" {
  count = var.enable_execute_command ? 1 : 0

  name   = "ecs-exec"
  role   = aws_iam_role.task.id
  policy = local.ecs_exec_policy
}

resource "aws_iam_role_policy" "task" {
  for_each = var.task_role_policies

  name   = each.key
  role   = aws_iam_role.task.id
  policy = each.value
}

# name_prefix com create_before_destroy: uma troca do grupo cria o novo
# antes de soltar o antigo, sem colisão de nome.
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "Tarefas do servico ECS ${var.name}: entrada so dos security groups autorizados."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "allowed" {
  for_each = var.allowed_security_groups

  security_group_id            = aws_security_group.this.id
  description                  = "Porta do conteiner a partir de ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = each.value
  tags                         = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

# Exceção do trivy (AWS-0104, saída irrestrita): sem NAT, as tarefas ficam em
# subnet pública e alcançam ECR, SSM, Secrets Manager, CloudWatch Logs e APIs
# externas pelos endpoints públicos, então a saída padrão precisa de
# 0.0.0.0/0. Ela fica restrita a TCP 443; endpoints de interface trocariam o
# risco por custo fixo por zona. Regras extras vêm de var.egress_rules.
#trivy:ignore:AWS-0104[from_port=443]
resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.egress_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.ip_protocol == "-1" ? null : each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  referenced_security_group_id = each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id
  tags                         = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

# Toda mudança na task definition (imagem nova, por exemplo) a substitui. Com
# skip_destroy, a substituição só tira a revisão antiga do estado, sem
# desregistrá-la: ela continua ACTIVE como alvo do rollback do circuit breaker
# e da volta manual. O provider lê o skip_destroy do estado anterior, então a
# primeira substituição depois de ligá-lo ainda desregistra a revisão antiga.
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode([local.container_definition])
  skip_destroy             = var.task_definition_skip_destroy
  tags                     = var.tags

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }
}

resource "aws_ecs_service" "this" {
  name                               = var.name
  cluster                            = var.cluster_arn
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  platform_version                   = "LATEST"
  enable_execute_command             = var.enable_execute_command
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  availability_zone_rebalancing      = var.availability_zone_rebalancing
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  health_check_grace_period_seconds  = var.target_group_arn == null ? null : var.health_check_grace_period_seconds
  wait_for_steady_state              = var.wait_for_steady_state
  tags                               = var.tags

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy

    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = concat([aws_security_group.this.id], var.additional_security_group_ids)
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [var.target_group_arn]

    content {
      target_group_arn = load_balancer.value
      container_name   = var.container_name
      container_port   = var.container_port
    }
  }

  # A contagem é do autoscaling (ou do console) depois da criação.
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    aws_iam_role_policy.execution,
    aws_iam_role_policy.task,
    aws_iam_role_policy.ecs_exec,
  ]
}

resource "aws_appautoscaling_target" "this" {
  count = var.autoscaling_max_capacity == null ? 0 : 1

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${local.cluster_name}/${aws_ecs_service.this.name}"
  min_capacity       = coalesce(var.autoscaling_min_capacity, var.desired_count)
  max_capacity       = var.autoscaling_max_capacity
  tags               = var.tags
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.autoscaling_max_capacity == null ? 0 : 1

  name               = "${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/ECS"
  metric_name         = each.value.metric_name
  statistic           = "Average"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  tags                = var.tags

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = aws_ecs_service.this.name
  }
}
