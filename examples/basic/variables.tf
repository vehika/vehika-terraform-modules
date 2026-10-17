variable "region" {
  description = "Região AWS onde a função é criada."
  type        = string
}

variable "name" {
  description = "Nome da função Lambda (também do log group, do alarme e da role)."
  type        = string
}

variable "filename" {
  description = "Caminho local do pacote .zip da função."
  type        = string
}

variable "handler" {
  description = "Ponto de entrada da função."
  type        = string
  default     = "index.handler"
}

variable "role_path" {
  description = "Caminho IAM da role de execução, começando e terminando com /."
  type        = string
}

variable "permissions_boundary_arn" {
  description = "ARN do permissions boundary aplicado à role de execução."
  type        = string
}

variable "alarm_actions" {
  description = "ARNs acionados quando o alarme de erros dispara e quando volta para OK."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags aplicadas aos recursos do exemplo."
  type        = map(string)
  default     = {}
}
