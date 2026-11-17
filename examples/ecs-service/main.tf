resource "aws_ecs_cluster" "this" {
  name = var.cluster_name
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

module "worker" {
  source = "../../ecs-service"

  name                     = var.name
  cluster_arn              = aws_ecs_cluster.this.arn
  vpc_id                   = var.vpc_id
  subnet_ids               = var.public_subnet_ids
  assign_public_ip         = true
  container_image          = var.container_image
  command                  = var.command
  role_path                = var.role_path
  permissions_boundary_arn = var.permissions_boundary_arn

  capacity_provider_strategy = [{ capacity_provider = "FARGATE_SPOT" }]

  secrets = var.secrets

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}
