variable "region" {
  description = "Região AWS da composição."
  type        = string
}

variable "name_prefix" {
  description = "Prefixo dos nomes de todos os recursos (ex.: <org>-<env>-<serviço>)."
  type        = string
}

variable "availability_zones" {
  description = "Zonas de disponibilidade da VPC (mínimo 2)."
  type        = list(string)
}

variable "certificate_arn" {
  description = "ARN do certificado do ACM já emitido para o domínio da API."
  type        = string
}

variable "container_image" {
  description = "Imagem ARM64 da aplicação (API e worker)."
  type        = string
}

variable "health_check_path" {
  description = "Caminho do health check da API."
  type        = string
  default     = "/health"
}

variable "worker_command" {
  description = "Comando do contêiner do worker."
  type        = list(string)
  default     = ["node", "dist/worker.js"]
}

variable "database_url_parameter_name" {
  description = "Nome do parâmetro SecureString com a URL do banco do usuário da aplicação, criado pelo administrador fora do Terraform."
  type        = string
}

variable "role_path" {
  description = "Caminho IAM das roles das tarefas, começando e terminando com /."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "ARN do permissions boundary das roles das tarefas."
  type        = string
}

variable "backup_replication_region" {
  description = "Região de destino da cópia dos backups do RDS."
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
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
