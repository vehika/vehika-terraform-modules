module "database" {
  source = "../../rds-postgres"

  identifier              = var.identifier
  vpc_id                  = var.vpc_id
  subnet_ids              = var.subnet_ids
  allowed_security_groups = var.allowed_security_groups
  kms_key_arn             = var.kms_key_arn

  backup_replication_enabled     = var.backup_replication_kms_key_arn != null
  backup_replication_region      = var.backup_replication_region
  backup_replication_kms_key_arn = var.backup_replication_kms_key_arn

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions
  tags          = var.tags
}
