# Composição vpc + alb + ecs-service + rds-postgres sem override: no plan, o
# ARN do target group, os IDs dos security groups e o ARN do segredo do RDS
# são desconhecidos. As regras de security group cruzadas não formam ciclo.

module "network" {
  source = "../../../vpc"

  name               = "example-net"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

module "alb" {
  source = "../../../alb"

  name                 = "example-alb"
  vpc_id               = module.network.vpc_id
  subnet_ids           = module.network.public_subnet_ids
  certificate_arn      = var.certificate_arn
  target_groups        = { api = { port = 3000 } }
  default_target_group = "api"

  target_security_groups = {
    api = { security_group_id = module.api.security_group_id, port = 3000 }
  }
}

module "database" {
  source = "../../../rds-postgres"

  identifier              = "example-db"
  vpc_id                  = module.network.vpc_id
  subnet_ids              = module.network.private_subnet_ids
  allowed_security_groups = { api = module.api.security_group_id }
}

module "api" {
  source = "../.."

  name                     = "example-api"
  cluster_arn              = var.cluster_arn
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.public_subnet_ids
  assign_public_ip         = true
  container_image          = "public.ecr.aws/example/app:1.0.0"
  container_port           = 3000
  target_group_arn         = module.alb.target_group_arns["api"]
  allowed_security_groups  = { alb = module.alb.security_group_id }
  role_path                = "/example/test/"
  permissions_boundary_arn = var.permissions_boundary_arn

  secrets = {
    DB_PASSWORD = "${module.database.master_user_secret_arn}:password::"
  }

  egress_rules = {
    https    = { description = "HTTPS", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    postgres = { description = "PostgreSQL", ip_protocol = "tcp", from_port = 5432, to_port = 5432, referenced_security_group_id = module.database.security_group_id }
  }
}
