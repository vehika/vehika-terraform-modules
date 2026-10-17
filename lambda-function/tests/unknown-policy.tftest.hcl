mock_provider "aws" {}

run "plans_with_policy_known_only_at_apply" {
  command = plan

  module {
    source = "./tests/unknown-policy"
  }

  variables {
    permissions_boundary_arn = "arn:aws:iam::${format("%012d", 0)}:policy/example/example-boundary"
  }

  assert {
    condition     = output.function_name == "example-fn"
    error_message = "O plan deve passar quando o JSON de additional_policies só é conhecido no apply."
  }
}
