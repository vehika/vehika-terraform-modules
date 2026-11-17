variable "name" {
  description = "Prefixo dos nomes (tag Name) da VPC e dos recursos dela. Também define, por padrão, o log group e a role dos flow logs."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,48}$", var.name))
    error_message = "name deve ter de 1 a 48 caracteres: letras, números e -."
  }
}

variable "cidr_block" {
  description = "Bloco CIDR IPv4 da VPC (de /16 a /24)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && tonumber(split("/", var.cidr_block)[1]) >= 16 && tonumber(split("/", var.cidr_block)[1]) <= 24
    error_message = "cidr_block deve ser um CIDR IPv4 válido, de /16 a /24."
  }
}

variable "availability_zones" {
  description = "Zonas de disponibilidade usadas (ex.: [\"us-east-1a\", \"us-east-1b\"]). Uma subnet pública e uma privada por zona. Mínimo 2."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 6 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "Informe de 2 a 6 zonas de disponibilidade distintas."
  }
}

variable "subnet_newbits" {
  description = "Bits somados à máscara da VPC para calcular cada subnet quando public_subnet_cidrs ou private_subnet_cidrs não são informados. Com /16 e 8, as subnets são /24: públicas a partir do índice 0 e privadas a partir da metade do espaço."
  type        = number
  default     = 8

  validation {
    condition     = var.subnet_newbits >= 2 && var.subnet_newbits <= 12 && floor(var.subnet_newbits) == var.subnet_newbits
    error_message = "subnet_newbits deve ser um inteiro entre 2 e 12."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas, um por zona e na mesma ordem de availability_zones. Nulo (padrão) calcula com subnet_newbits."
  type        = list(string)
  default     = null

  validation {
    condition     = var.public_subnet_cidrs == null || (length(coalesce(var.public_subnet_cidrs, [])) == length(var.availability_zones) && alltrue([for cidr in coalesce(var.public_subnet_cidrs, []) : can(cidrhost(cidr, 0))]))
    error_message = "public_subnet_cidrs deve ter um CIDR IPv4 válido por zona de disponibilidade."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas, um por zona e na mesma ordem de availability_zones. Nulo (padrão) calcula com subnet_newbits."
  type        = list(string)
  default     = null

  validation {
    condition     = var.private_subnet_cidrs == null || (length(coalesce(var.private_subnet_cidrs, [])) == length(var.availability_zones) && alltrue([for cidr in coalesce(var.private_subnet_cidrs, []) : can(cidrhost(cidr, 0))]))
    error_message = "private_subnet_cidrs deve ter um CIDR IPv4 válido por zona de disponibilidade."
  }
}

variable "nat_gateway_mode" {
  description = "NAT das subnets privadas: none (padrão, sem custo; as subnets privadas não saem para a internet), single (um NAT para todas as zonas) ou one_per_az (um NAT por zona, para alta disponibilidade). Cada NAT custa por hora e por GB processado."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "single", "one_per_az"], var.nat_gateway_mode)
    error_message = "nat_gateway_mode deve ser none, single ou one_per_az."
  }
}

variable "s3_gateway_endpoint_enabled" {
  description = "Cria o endpoint gateway do S3 (sem custo) associado a todas as tabelas de rota, públicas e privadas."
  type        = bool
  default     = true
}

variable "s3_gateway_endpoint_policy" {
  description = "Documento JSON da política do endpoint do S3. Nulo (padrão) usa a política padrão da AWS (acesso total, limitado pelas políticas IAM e dos buckets)."
  type        = string
  default     = null

  validation {
    condition     = var.s3_gateway_endpoint_policy == null || can(jsondecode(var.s3_gateway_endpoint_policy))
    error_message = "s3_gateway_endpoint_policy deve ser um documento JSON válido."
  }
}

variable "flow_logs_enabled" {
  description = "Habilita os flow logs da VPC."
  type        = bool
  default     = false
}

variable "flow_logs_destination_type" {
  description = "Destino dos flow logs: cloud-watch-logs (log group e role criados pelo módulo) ou s3 (bucket informado em flow_logs_s3_bucket_arn)."
  type        = string
  default     = "cloud-watch-logs"

  validation {
    condition     = contains(["cloud-watch-logs", "s3"], var.flow_logs_destination_type)
    error_message = "flow_logs_destination_type deve ser cloud-watch-logs ou s3."
  }
}

variable "flow_logs_traffic_type" {
  description = "Tráfego registrado nos flow logs: ALL, ACCEPT ou REJECT."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type deve ser ALL, ACCEPT ou REJECT."
  }
}

variable "flow_logs_max_aggregation_interval" {
  description = "Intervalo máximo de agregação dos flow logs, em segundos: 60 ou 600."
  type        = number
  default     = 600

  validation {
    condition     = contains([60, 600], var.flow_logs_max_aggregation_interval)
    error_message = "flow_logs_max_aggregation_interval deve ser 60 ou 600."
  }
}

variable "flow_logs_s3_bucket_arn" {
  description = "ARN do bucket (opcionalmente com prefixo, arn:<partição>:s3:::<bucket>/<prefixo>) que recebe os flow logs quando o destino é s3. A bucket policy precisa permitir o serviço delivery.logs.amazonaws.com."
  type        = string
  default     = null

  validation {
    condition     = var.flow_logs_s3_bucket_arn == null || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9.-]{3,63}(/.*)?$", var.flow_logs_s3_bucket_arn))
    error_message = "flow_logs_s3_bucket_arn deve ser o ARN de um bucket S3 (arn:<partição>:s3:::<bucket>[/<prefixo>])."
  }

  validation {
    condition     = !(var.flow_logs_enabled && var.flow_logs_destination_type == "s3" && var.flow_logs_s3_bucket_arn == null)
    error_message = "Com flow logs no destino s3, informe flow_logs_s3_bucket_arn."
  }
}

variable "flow_logs_log_group_name" {
  description = "Nome do log group dos flow logs (destino cloud-watch-logs). Nulo (padrão) usa /vpc/<name>/flow-logs."
  type        = string
  default     = null

  validation {
    condition     = var.flow_logs_log_group_name == null || can(regex("^[A-Za-z0-9_./#-]{1,512}$", var.flow_logs_log_group_name))
    error_message = "flow_logs_log_group_name deve ter de 1 a 512 caracteres: letras, números e _./#-."
  }
}

variable "flow_logs_retention_in_days" {
  description = "Retenção do log group dos flow logs, em dias. Aceita os valores do CloudWatch Logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_in_days)
    error_message = "flow_logs_retention_in_days deve ser um dos valores aceitos pelo CloudWatch Logs: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 ou 3653."
  }
}

variable "flow_logs_kms_key_arn" {
  description = "ARN de uma chave KMS para o log group dos flow logs. Nulo (padrão) usa a criptografia gerenciada pelo CloudWatch Logs."
  type        = string
  default     = null

  validation {
    condition     = var.flow_logs_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.flow_logs_kms_key_arn))
    error_message = "flow_logs_kms_key_arn deve ser o ARN de uma chave KMS (arn:<partição>:kms:...)."
  }
}

variable "flow_logs_role_name" {
  description = "Nome da role que entrega os flow logs no CloudWatch Logs. Nulo (padrão) usa <name>-flow-logs."
  type        = string
  default     = null

  validation {
    condition     = var.flow_logs_role_name == null || can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.flow_logs_role_name))
    error_message = "O nome da role deve ter de 1 a 64 caracteres: letras, números e _+=,.@-."
  }
}

variable "role_path" {
  description = "Caminho IAM da role dos flow logs, começando e terminando com /. Obrigatório quando os flow logs vão para o CloudWatch Logs."
  type        = string
  default     = null

  validation {
    condition     = var.role_path == null || can(regex("^/([A-Za-z0-9_+=,.@-]+/)*$", coalesce(var.role_path, "/")))
    error_message = "O caminho IAM deve começar e terminar com /."
  }

  validation {
    condition     = !(var.flow_logs_enabled && var.flow_logs_destination_type == "cloud-watch-logs" && var.role_path == null)
    error_message = "Com flow logs no CloudWatch Logs, informe role_path."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN da política usada como permissions boundary da role dos flow logs. Obrigatório quando os flow logs vão para o CloudWatch Logs."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws(-[a-z]+)*:iam::([0-9]{12}|aws):policy/[A-Za-z0-9_+=,.@/-]+$", coalesce(var.permissions_boundary_arn, "-")))
    error_message = "permissions_boundary_arn deve ser o ARN de uma política IAM (arn:<partição>:iam::<conta>:policy/<nome>)."
  }

  validation {
    condition     = !(var.flow_logs_enabled && var.flow_logs_destination_type == "cloud-watch-logs" && var.permissions_boundary_arn == null)
    error_message = "Com flow logs no CloudWatch Logs, informe permissions_boundary_arn."
  }
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos que aceitam tags."
  type        = map(string)
  default     = {}
}
