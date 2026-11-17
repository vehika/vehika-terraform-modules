variable "region" {
  description = "Região AWS onde o cluster e o serviço são criados."
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster ECS criado pelo exemplo."
  type        = string
}

variable "name" {
  description = "Nome do serviço ECS."
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC do serviço."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets públicas das tarefas (sem NAT, com IP público)."
  type        = list(string)
}

variable "container_image" {
  description = "Imagem ARM64 do contêiner."
  type        = string
}

variable "command" {
  description = "Comando do contêiner. Nulo usa o da imagem."
  type        = list(string)
  default     = null
}

variable "secrets" {
  description = "Variável de ambiente => nome ou ARN do parâmetro SSM (ou ARN do Secrets Manager)."
  type        = map(string)
  default     = {}
}

variable "role_path" {
  description = "Caminho IAM das roles, começando e terminando com /."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "ARN do permissions boundary das roles."
  type        = string
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
