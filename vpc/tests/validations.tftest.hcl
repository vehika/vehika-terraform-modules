mock_provider "aws" {}

variables {
  name               = "example-net"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

run "rejects_single_az" {
  command = plan

  variables {
    availability_zones = ["us-east-1a"]
  }

  expect_failures = [var.availability_zones]
}

run "rejects_duplicated_az" {
  command = plan

  variables {
    availability_zones = ["us-east-1a", "us-east-1a"]
  }

  expect_failures = [var.availability_zones]
}

run "rejects_invalid_cidr" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/8"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_invalid_nat_mode" {
  command = plan

  variables {
    nat_gateway_mode = "always"
  }

  expect_failures = [var.nat_gateway_mode]
}

run "rejects_subnet_cidrs_count_mismatch" {
  command = plan

  variables {
    public_subnet_cidrs = ["10.0.0.0/24"]
  }

  expect_failures = [var.public_subnet_cidrs]
}

run "rejects_cloudwatch_flow_logs_without_boundary" {
  command = plan

  variables {
    flow_logs_enabled = true
    role_path         = "/example/test/"
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_cloudwatch_flow_logs_without_role_path" {
  command = plan

  variables {
    flow_logs_enabled        = true
    permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
  }

  expect_failures = [var.role_path]
}

run "rejects_s3_flow_logs_without_bucket" {
  command = plan

  variables {
    flow_logs_enabled          = true
    flow_logs_destination_type = "s3"
  }

  expect_failures = [var.flow_logs_s3_bucket_arn]
}

run "rejects_invalid_boundary" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:role/example-role"
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "rejects_invalid_endpoint_policy" {
  command = plan

  variables {
    s3_gateway_endpoint_policy = "{ isso não é json"
  }

  expect_failures = [var.s3_gateway_endpoint_policy]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "nome com espaço"
  }

  expect_failures = [var.name]
}
