variable "region" {
  description = "Região AWS onde a instância é criada."
  type        = string
}

variable "identifier" {
  description = "Identificador da instância RDS."
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC da instância."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets privadas do subnet group (pelo menos duas zonas)."
  type        = list(string)
}

variable "allowed_security_groups" {
  description = "Security groups autorizados a conectar no banco: nome lógico => ID."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "ARN da CMK do armazenamento. Nulo usa aws/rds."
  type        = string
  default     = null
}

variable "backup_replication_region" {
  description = "Região de destino da cópia dos backups automáticos."
  type        = string
  default     = "us-east-2"
}

variable "backup_replication_kms_key_arn" {
  description = "ARN da chave KMS na região de destino. Nulo desliga a replicação."
  type        = string
  default     = null
}

variable "alarm_actions" {
  description = "ARNs acionados quando um alarme dispara e quando volta para OK."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags aplicadas aos recursos do exemplo."
  type        = map(string)
  default     = {}
}
