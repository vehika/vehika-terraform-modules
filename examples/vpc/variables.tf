variable "region" {
  description = "Região AWS onde a VPC é criada."
  type        = string
}

variable "name" {
  description = "Prefixo dos nomes da VPC e dos recursos dela."
  type        = string
}

variable "availability_zones" {
  description = "Zonas de disponibilidade da VPC (mínimo 2)."
  type        = list(string)
}

variable "nat_gateway_mode" {
  description = "NAT das subnets privadas: none, single ou one_per_az."
  type        = string
  default     = "none"
}

variable "tags" {
  description = "Tags aplicadas aos recursos do exemplo."
  type        = map(string)
  default     = {}
}
