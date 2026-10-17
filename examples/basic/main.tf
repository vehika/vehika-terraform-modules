module "function" {
  source = "../../lambda-function"

  name                     = var.name
  description              = "Exemplo do módulo lambda-function."
  filename                 = var.filename
  source_code_hash         = filebase64sha256(var.filename)
  handler                  = var.handler
  role_path                = var.role_path
  permissions_boundary_arn = var.permissions_boundary_arn
  alarm_actions            = var.alarm_actions
  ok_actions               = var.alarm_actions
  tags                     = var.tags

  environment_variables = {
    POWERTOOLS_SERVICE_NAME = var.name
  }
}
