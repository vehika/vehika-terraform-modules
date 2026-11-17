# Composição completa: VPC sem NAT, ALB público com WAF, API e worker no
# Fargate ARM64 em subnet pública (IP público, sem entrada da internet) e RDS
# PostgreSQL na subnet privada. As referências cruzadas entre security groups
# usam regras separadas e não formam ciclo:
#   ALB -> saída para o SG da API | API -> entrada só do SG do ALB
#   API e worker -> saída 5432 para o SG do RDS | RDS -> entrada só deles

locals {
  container_port = 3000

  database_egress = {
    description                  = "PostgreSQL para o RDS"
    ip_protocol                  = "tcp"
    from_port                    = 5432
    to_port                      = 5432
    referenced_security_group_id = module.database.security_group_id
  }

  https_egress = {
    description = "HTTPS para a internet (ECR, SSM, logs e APIs externas)"
    ip_protocol = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_ipv4   = "0.0.0.0/0"
  }
}

module "network" {
  source = "../../vpc"

  name               = var.name_prefix
  availability_zones = var.availability_zones
  tags               = var.tags
}

module "alb" {
  source = "../../alb"

  name            = "${var.name_prefix}-alb"
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.public_subnet_ids
  certificate_arn = var.certificate_arn

  target_groups = {
    api = { port = local.container_port, health_check = { path = var.health_check_path } }
  }
  default_target_group = "api"

  target_security_groups = {
    api = { security_group_id = module.api.security_group_id, port = local.container_port }
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name_prefix
  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

module "api" {
  source = "../../ecs-service"

  name                     = "${var.name_prefix}-api"
  cluster_arn              = aws_ecs_cluster.this.arn
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.public_subnet_ids
  assign_public_ip         = true
  container_image          = var.container_image
  container_port           = local.container_port
  desired_count            = 2
  autoscaling_max_capacity = 4
  target_group_arn         = module.alb.target_group_arns["api"]
  allowed_security_groups  = { alb = module.alb.security_group_id }
  role_path                = var.role_path
  permissions_boundary_arn = var.permissions_boundary_arn

  secrets = {
    DATABASE_URL = var.database_url_parameter_name
  }

  egress_rules = {
    https    = local.https_egress
    postgres = local.database_egress
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

module "worker" {
  source = "../../ecs-service"

  name                     = "${var.name_prefix}-worker"
  cluster_arn              = aws_ecs_cluster.this.arn
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.public_subnet_ids
  assign_public_ip         = true
  container_image          = var.container_image
  command                  = var.worker_command
  role_path                = var.role_path
  permissions_boundary_arn = var.permissions_boundary_arn

  # FARGATE (padrão) com ARM64 (padrão): a documentação do ECS não confirma
  # Fargate Spot com ARM64.
  capacity_provider_strategy = [{ capacity_provider = "FARGATE" }]

  # Uma tarefa só por vez: no deploy, a antiga para antes de a nova subir, e
  # os crons não rodam em dobro. A AWS não aceita o rebalanceamento entre
  # zonas com maximumPercent de 100%, então ele fica desligado. stop_timeout
  # de 120 s dá tempo para terminar o trabalho em andamento no SIGTERM.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  availability_zone_rebalancing      = "DISABLED"
  stop_timeout                       = 120

  secrets = {
    DATABASE_URL = var.database_url_parameter_name
  }

  egress_rules = {
    https    = local.https_egress
    postgres = local.database_egress
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

module "database" {
  source = "../../rds-postgres"

  identifier = "${var.name_prefix}-db"
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids

  allowed_security_groups = {
    api    = module.api.security_group_id
    worker = module.worker.security_group_id
  }

  backup_replication_enabled     = var.backup_replication_kms_key_arn != null
  backup_replication_region      = var.backup_replication_region
  backup_replication_kms_key_arn = var.backup_replication_kms_key_arn

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags
}
