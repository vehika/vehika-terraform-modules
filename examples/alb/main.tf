module "alb" {
  source = "../../alb"

  name            = var.name
  vpc_id          = var.vpc_id
  subnet_ids      = var.public_subnet_ids
  certificate_arn = var.certificate_arn

  target_groups = {
    api = {
      port         = var.container_port
      health_check = { path = var.health_check_path }
    }
  }
  default_target_group = "api"

  target_security_groups = {
    api = { security_group_id = var.api_security_group_id, port = var.container_port }
  }

  access_logs_bucket = var.access_logs_bucket

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags
}
