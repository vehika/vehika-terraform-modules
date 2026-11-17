mock_provider "aws" {}

variables {
  cluster_arn              = "arn:aws:ecs:us-east-1:${format("%012d", 0)}:cluster/example-cluster"
  certificate_arn          = "arn:aws:acm:us-east-1:${format("%012d", 0)}:certificate/example-certificate"
  permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
}

run "plans_composition_with_unknown_values" {
  command = plan

  module {
    source = "./tests/composition"
  }

  assert {
    condition     = output.service_name == "example-api" && output.database_identifier == "example-db" && output.target_group_name == "example-alb-api"
    error_message = "O plan da composição deve passar com o target group, os security groups e o segredo do RDS conhecidos só no apply."
  }
}
