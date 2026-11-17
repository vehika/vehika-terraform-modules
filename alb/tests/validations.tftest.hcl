mock_provider "aws" {}

variables {
  name            = "example-alb"
  vpc_id          = "vpc-0example"
  subnet_ids      = ["subnet-0example1", "subnet-0example2"]
  certificate_arn = "arn:aws:acm:us-east-1:${format("%012d", 0)}:certificate/example-certificate"
}

run "accepts_defaults_without_overrides" {
  command = plan

  assert {
    condition     = aws_lb.this.name == "example-alb"
    error_message = "O plan com os padrões deve passar sem override."
  }
}

run "rejects_name_longer_than_32" {
  command = plan

  variables {
    name = join("", [for index in range(33) : "a"])
  }

  expect_failures = [var.name]
}

run "rejects_internal_prefix" {
  command = plan

  variables {
    name = "internal-example"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_certificate" {
  command = plan

  variables {
    certificate_arn = "arn:aws:iam::${format("%012d", 0)}:server-certificate/example"
  }

  expect_failures = [var.certificate_arn]
}

run "rejects_legacy_tls_policy" {
  command = plan

  variables {
    ssl_policy = "ELBSecurityPolicy-2016-08"
  }

  expect_failures = [var.ssl_policy]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0example1"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_unknown_default_target_group" {
  command = plan

  variables {
    default_target_group = "api"
  }

  expect_failures = [var.default_target_group]
}

run "rejects_rule_without_condition" {
  command = plan

  variables {
    target_groups  = { api = { port = 3000 } }
    listener_rules = { api = { priority = 1, target_group = "api" } }
  }

  expect_failures = [var.listener_rules]
}

run "rejects_rule_with_unknown_target_group" {
  command = plan

  variables {
    target_groups  = { api = { port = 3000 } }
    listener_rules = { other = { priority = 1, target_group = "other", path_patterns = ["/x"] } }
  }

  expect_failures = [var.listener_rules]
}

run "rejects_duplicated_rule_priority" {
  command = plan

  variables {
    target_groups = { api = { port = 3000 } }
    listener_rules = {
      one = { priority = 1, target_group = "api", path_patterns = ["/a"] }
      two = { priority = 1, target_group = "api", path_patterns = ["/b"] }
    }
  }

  expect_failures = [var.listener_rules]
}

run "rejects_target_group_name_longer_than_32" {
  command = plan

  variables {
    name          = "example-alb-with-a-long-name"
    target_groups = { api-service = { port = 3000 } }
  }

  expect_failures = [aws_lb_target_group.this]
}

run "rejects_low_rate_limit" {
  command = plan

  variables {
    waf_rate_limit = 5
  }

  expect_failures = [var.waf_rate_limit]
}

run "rejects_unknown_waf_override_group" {
  command = plan

  variables {
    waf_rule_count_overrides = { sql = ["SQLi_BODY"] }
  }

  expect_failures = [var.waf_rule_count_overrides]
}

run "rejects_waf_log_destination_without_prefix" {
  command = plan

  variables {
    waf_log_destination_arn = "arn:aws:logs:us-east-1:${format("%012d", 0)}:log-group:example"
  }

  expect_failures = [var.waf_log_destination_arn]
}

run "rejects_invalid_ingress_cidr" {
  command = plan

  variables {
    ingress_cidr_blocks = ["internet"]
  }

  expect_failures = [var.ingress_cidr_blocks]
}
