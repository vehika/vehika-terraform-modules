variable "region" {
  description = "Região AWS onde o ALB é criado."
  type        = string
}

variable "name" {
  description = "Nome do ALB (até 32 caracteres)."
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC do ALB."
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets públicas do ALB (pelo menos duas zonas)."
  type        = list(string)
}

variable "certificate_arn" {
  description = "ARN do certificado do ACM já validado."
  type        = string
}

variable "container_port" {
  description = "Porta do contêiner da API."
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Caminho do health check da API."
  type        = string
  default     = "/health"
}

variable "api_security_group_id" {
  description = "ID do security group das tarefas da API."
  type        = string
}

variable "access_logs_bucket" {
  description = "Bucket dos access logs. Nulo desliga."
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
