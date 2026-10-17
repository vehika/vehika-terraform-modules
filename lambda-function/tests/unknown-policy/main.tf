resource "aws_sqs_queue" "example" {
  name                    = "example-queue"
  sqs_managed_sse_enabled = true
}

data "aws_iam_policy_document" "queue_access" {
  statement {
    sid       = "SendToQueue"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.example.arn]
  }
}

module "function" {
  source = "../.."

  name                     = "example-fn"
  filename                 = "function.zip"
  source_code_hash         = "bW9jay1oYXNo"
  handler                  = "index.handler"
  role_path                = "/example/test/"
  permissions_boundary_arn = var.permissions_boundary_arn

  additional_policies = {
    queue-access = data.aws_iam_policy_document.queue_access.json
  }
}
