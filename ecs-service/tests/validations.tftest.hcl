mock_provider "aws" {}

variables {
  name                     = "example-api"
  cluster_arn              = "arn:aws:ecs:us-east-1:${format("%012d", 0)}:cluster/example-cluster"
  vpc_id                   = "vpc-0example"
  subnet_ids               = ["subnet-0example1", "subnet-0example2"]
  container_image          = "public.ecr.aws/example/app:1.0.0"
  role_path                = "/example/test/"
  permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
}

run "accepts_defaults_without_overrides" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.name == "example-api" && aws_iam_role.task.permissions_boundary == var.permissions_boundary_arn
    error_message = "O plan com os padrões deve passar sem override."
  }
}

run "rejects_null_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = null
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_empty_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = ""
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_role_arn_as_permissions_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:role/example-role"
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_role_path_without_trailing_slash" {
  command = plan

  variables {
    role_path = "/example/test"
  }

  expect_failures = [var.role_path]
}

run "rejects_invalid_cluster_arn" {
  command = plan

  variables {
    cluster_arn = "example-cluster"
  }

  expect_failures = [var.cluster_arn]
}

run "rejects_invalid_memory_for_cpu" {
  command = plan

  variables {
    cpu    = 256
    memory = 4096
  }

  expect_failures = [var.memory]
}

run "rejects_invalid_cpu" {
  command = plan

  variables {
    cpu = 300
  }

  expect_failures = [var.cpu]
}

run "rejects_invalid_architecture" {
  command = plan

  variables {
    cpu_architecture = "arm64"
  }

  expect_failures = [var.cpu_architecture]
}

run "rejects_unknown_capacity_provider" {
  command = plan

  variables {
    capacity_provider_strategy = [{ capacity_provider = "EC2" }]
  }

  expect_failures = [var.capacity_provider_strategy]
}

run "rejects_duplicated_capacity_provider" {
  command = plan

  variables {
    capacity_provider_strategy = [{ capacity_provider = "FARGATE" }, { capacity_provider = "FARGATE" }]
  }

  expect_failures = [var.capacity_provider_strategy]
}

run "rejects_target_group_without_port" {
  command = plan

  variables {
    target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:${format("%012d", 0)}:targetgroup/example-api/0000000000000000"
  }

  expect_failures = [var.target_group_arn]
}

run "rejects_ingress_without_port" {
  command = plan

  variables {
    allowed_security_groups = { alb = "sg-0examplealb" }
  }

  expect_failures = [var.allowed_security_groups]
}

run "rejects_secret_value_that_is_not_a_reference" {
  command = plan

  variables {
    secrets = { DATABASE_URL = "postgres://usuario senha@host/banco" }
  }

  expect_failures = [var.secrets]
}

run "rejects_variable_in_environment_and_secrets" {
  command = plan

  variables {
    environment = { DATABASE_URL = "x" }
    secrets     = { DATABASE_URL = "/example/test/api/database-url" }
  }

  expect_failures = [var.secrets]
}

run "rejects_egress_rule_with_two_destinations" {
  command = plan

  variables {
    egress_rules = {
      both = { description = "x", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0", referenced_security_group_id = "sg-0example" }
    }
  }

  expect_failures = [var.egress_rules]
}

run "rejects_autoscaling_min_above_max" {
  command = plan

  variables {
    desired_count            = 3
    autoscaling_max_capacity = 2
  }

  expect_failures = [var.autoscaling_min_capacity]
}

run "rejects_task_policy_named_ecs_exec" {
  command = plan

  variables {
    task_role_policies = { ecs-exec = jsonencode({ Version = "2012-10-17", Statement = [] }) }
  }

  expect_failures = [var.task_role_policies]
}

run "rejects_invalid_task_policy_document" {
  command = plan

  variables {
    task_role_policies = { extra = "{ isso não é json" }
  }

  expect_failures = [var.task_role_policies]
}

run "rejects_invalid_stop_timeout" {
  command = plan

  variables {
    stop_timeout = 121
  }

  expect_failures = [var.stop_timeout]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "nome com espaço"
  }

  expect_failures = [var.name]
}
