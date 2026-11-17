variable "name" {
  description = "Nome do ALB (até 32 caracteres). Também nomeia o security group, a web ACL do WAF, os alarmes e, por padrão, os target groups (<name>-<chave>)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", var.name)) && !startswith(lower(var.name), "internal-")
    error_message = "name deve ter de 1 a 32 caracteres (letras, números e -), sem começar ou terminar com - e sem começar com internal-."
  }
}

variable "vpc_id" {
  description = "ID da VPC do ALB e dos target groups."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets do ALB, em pelo menos duas zonas (públicas para um ALB voltado à internet)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Informe pelo menos duas subnets, em zonas diferentes."
  }
}

variable "internal" {
  description = "Cria um ALB interno (sem endereço público). Padrão false: ALB voltado à internet."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN do certificado do ACM, na mesma região, usado pelo listener HTTPS. O módulo não cria nem valida certificados: a validação por DNS fica com quem controla o domínio."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/[A-Za-z0-9-]+$", var.certificate_arn))
    error_message = "certificate_arn deve ser o ARN de um certificado do ACM (arn:<partição>:acm:<região>:<conta>:certificate/<id>)."
  }
}

variable "additional_certificate_arns" {
  description = "Certificados extras do ACM no listener HTTPS (SNI), além de certificate_arn."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for certificate_arn in var.additional_certificate_arns : can(regex("^arn:aws[a-z-]*:acm:[a-z0-9-]+:[0-9]{12}:certificate/[A-Za-z0-9-]+$", certificate_arn))])
    error_message = "Cada item de additional_certificate_arns deve ser o ARN de um certificado do ACM."
  }
}

variable "ssl_policy" {
  description = "Política de TLS do listener HTTPS. O padrão aceita TLS 1.3 e 1.2 com cifras modernas. Só políticas de TLS 1.2 ou superior são aceitas."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  validation {
    condition     = can(regex("^ELBSecurityPolicy-(TLS13-|TLS-1-2-|FS-1-2-)", var.ssl_policy))
    error_message = "ssl_policy deve ser uma política de TLS 1.2 ou superior (ELBSecurityPolicy-TLS13-*, ELBSecurityPolicy-TLS-1-2-* ou ELBSecurityPolicy-FS-1-2-*)."
  }
}

variable "ingress_cidr_blocks" {
  description = "CIDRs IPv4 que podem acessar as portas 80 e 443 do ALB. O padrão é a internet inteira (ALB público); a porta 80 só redireciona para 443."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.ingress_cidr_blocks) >= 1 && alltrue([for cidr in var.ingress_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "ingress_cidr_blocks deve ter pelo menos um CIDR IPv4 válido."
  }
}

variable "target_security_groups" {
  description = "Destinos da saída do ALB: chave = nome lógico (conhecido no plan), security_group_id = SG das tarefas, port = porta do contêiner (tráfego e health check). Sem itens, o ALB não alcança nenhum alvo."
  type = map(object({
    security_group_id = string
    port              = number
  }))
  default = {}

  validation {
    condition     = alltrue([for rule_name in keys(var.target_security_groups) : can(regex("^[A-Za-z0-9_-]{1,64}$", rule_name))])
    error_message = "As chaves de target_security_groups devem ter de 1 a 64 caracteres: letras, números, _ e -."
  }

  validation {
    condition     = alltrue([for target in values(var.target_security_groups) : target.port >= 1 && target.port <= 65535 && floor(target.port) == target.port])
    error_message = "port deve ser um inteiro entre 1 e 65535."
  }
}

variable "target_groups" {
  description = "Target groups do tipo ip (Fargate), por chave lógica. name é opcional (padrão <name>-<chave>, até 32 caracteres). health_check aceita path, matcher, interval, timeout, healthy_threshold e unhealthy_threshold."
  type = map(object({
    name                 = optional(string)
    port                 = number
    protocol             = optional(string, "HTTP")
    protocol_version     = optional(string, "HTTP1")
    deregistration_delay = optional(number, 30)
    slow_start           = optional(number, 0)
    health_check = optional(object({
      path                = optional(string, "/")
      matcher             = optional(string, "200-399")
      interval            = optional(number, 15)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 3)
    }), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for target_key in keys(var.target_groups) : can(regex("^[A-Za-z0-9-]{1,32}$", target_key))])
    error_message = "As chaves de target_groups devem ter de 1 a 32 caracteres: letras, números e -."
  }

  validation {
    condition     = alltrue([for target_group in values(var.target_groups) : contains(["HTTP", "HTTPS"], target_group.protocol) && contains(["HTTP1", "HTTP2", "GRPC"], target_group.protocol_version)])
    error_message = "protocol deve ser HTTP ou HTTPS, e protocol_version HTTP1, HTTP2 ou GRPC."
  }

  validation {
    condition     = alltrue([for target_group in values(var.target_groups) : target_group.port >= 1 && target_group.port <= 65535 && target_group.deregistration_delay >= 0 && target_group.deregistration_delay <= 3600])
    error_message = "port deve estar entre 1 e 65535, e deregistration_delay entre 0 e 3600."
  }

  validation {
    condition     = alltrue([for target_group in values(var.target_groups) : target_group.name == null || can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,30}[A-Za-z0-9])?$", coalesce(target_group.name, "-")))])
    error_message = "O name de um target group deve ter de 1 a 32 caracteres (letras, números e -), sem começar ou terminar com -."
  }
}

variable "default_target_group" {
  description = "Chave do target group que recebe o tráfego HTTPS sem regra específica. Nulo (padrão) responde 404 fixo."
  type        = string
  default     = null

  validation {
    condition     = var.default_target_group == null || contains(keys(var.target_groups), coalesce(var.default_target_group, "-"))
    error_message = "default_target_group deve ser uma chave de target_groups."
  }
}

variable "listener_rules" {
  description = "Regras do listener HTTPS, por chave lógica: priority (1 a 50000, única), target_group (chave de target_groups) e pelo menos uma condição (host_headers e/ou path_patterns)."
  type = map(object({
    priority      = number
    target_group  = string
    host_headers  = optional(list(string), [])
    path_patterns = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for rule in values(var.listener_rules) : contains(keys(var.target_groups), rule.target_group)])
    error_message = "O target_group de cada regra deve ser uma chave de target_groups."
  }

  validation {
    condition     = alltrue([for rule in values(var.listener_rules) : rule.priority >= 1 && rule.priority <= 50000 && (length(rule.host_headers) + length(rule.path_patterns)) > 0])
    error_message = "Cada regra precisa de priority entre 1 e 50000 e de pelo menos um host_headers ou path_patterns."
  }

  validation {
    condition     = length(distinct([for rule in values(var.listener_rules) : rule.priority])) == length(var.listener_rules)
    error_message = "As prioridades das regras devem ser únicas."
  }
}

variable "idle_timeout" {
  description = "Tempo ocioso das conexões, em segundos (1 a 4000)."
  type        = number
  default     = 60

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout deve estar entre 1 e 4000."
  }
}

variable "desync_mitigation_mode" {
  description = "Proteção contra HTTP desync: monitor, defensive (padrão) ou strictest."
  type        = string
  default     = "defensive"

  validation {
    condition     = contains(["monitor", "defensive", "strictest"], var.desync_mitigation_mode)
    error_message = "desync_mitigation_mode deve ser monitor, defensive ou strictest."
  }
}

variable "deletion_protection" {
  description = "Impede apagar o ALB. Para destruir, desligue antes num apply separado."
  type        = bool
  default     = true
}

variable "hsts_header_value" {
  description = "Valor do cabeçalho Strict-Transport-Security que o ALB acrescenta às respostas HTTPS (ex.: max-age=31536000; includeSubDomains). Nulo (padrão) não altera o cabeçalho da aplicação."
  type        = string
  default     = null
}

variable "access_logs_bucket" {
  description = "Nome do bucket S3 dos access logs do ALB. Nulo (padrão) desliga os access logs. A bucket policy precisa permitir a entrega de logs do ELB e o bucket usa SSE-S3 (o ELB não grava com SSE-KMS)."
  type        = string
  default     = null

  validation {
    condition     = var.access_logs_bucket == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", coalesce(var.access_logs_bucket, "-")))
    error_message = "access_logs_bucket deve ser um nome de bucket S3 válido."
  }
}

variable "access_logs_prefix" {
  description = "Prefixo dos access logs no bucket. Nulo (padrão) usa o nome do ALB."
  type        = string
  default     = null
}

variable "waf_enabled" {
  description = "Cria e associa a web ACL do WAFv2 com rate limit por IP e as regras gerenciadas Common, KnownBadInputs e IpReputation."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Requisições por IP dentro da janela waf_rate_limit_window a partir das quais o WAF bloqueia o IP (mínimo 10)."
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 10 && var.waf_rate_limit <= 2000000000 && floor(var.waf_rate_limit) == var.waf_rate_limit
    error_message = "waf_rate_limit deve ser um inteiro entre 10 e 2000000000."
  }
}

variable "waf_rate_limit_window" {
  description = "Janela do rate limit, em segundos: 60, 120, 300 ou 600."
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 120, 300, 600], var.waf_rate_limit_window)
    error_message = "waf_rate_limit_window deve ser 60, 120, 300 ou 600."
  }
}

variable "waf_forwarded_ip_header" {
  description = "Cabeçalho com o IP real do cliente quando há proxy na frente do ALB (ex.: CF-Connecting-IP ou X-Forwarded-For). Nulo (padrão) usa o IP de origem da conexão. Com proxy e sem este cabeçalho, o rate limit agrupa todos os clientes no IP do proxy. Use só atrás de proxy confiável e com ingress_cidr_blocks limitado a ele: sem isso, o cliente forja o cabeçalho."
  type        = string
  default     = null

  validation {
    condition     = var.waf_forwarded_ip_header == null || can(regex("^[A-Za-z0-9-]{1,64}$", coalesce(var.waf_forwarded_ip_header, "-")))
    error_message = "waf_forwarded_ip_header deve ser um nome de cabeçalho (letras, números e -)."
  }
}

variable "waf_rule_count_overrides" {
  description = "Regras das regras gerenciadas que passam de bloquear para só contar, por grupo: common, known_bad_inputs ou ip_reputation (ex.: { common = [\"SizeRestrictions_BODY\"] } para aceitar corpos acima de 8 KB)."
  type        = map(list(string))
  default     = {}

  validation {
    condition     = alltrue([for group in keys(var.waf_rule_count_overrides) : contains(["common", "known_bad_inputs", "ip_reputation"], group)])
    error_message = "As chaves de waf_rule_count_overrides devem ser common, known_bad_inputs ou ip_reputation."
  }
}

variable "waf_log_destination_arn" {
  description = "ARN do destino dos logs do WAF: log group, bucket S3 ou Firehose cujo nome começa com aws-waf-logs-. Nulo (padrão) não registra. Os cabeçalhos authorization e cookie são omitidos."
  type        = string
  default     = null

  validation {
    condition     = var.waf_log_destination_arn == null || can(regex("^arn:aws[a-z-]*:(logs|s3|firehose):.*aws-waf-logs-", coalesce(var.waf_log_destination_arn, "-")))
    error_message = "waf_log_destination_arn deve ser o ARN de um log group, bucket ou Firehose cujo nome começa com aws-waf-logs-."
  }
}

variable "alarm_period" {
  description = "Período dos alarmes, em segundos (múltiplo de 60)."
  type        = number
  default     = 300

  validation {
    condition     = var.alarm_period >= 60 && var.alarm_period % 60 == 0
    error_message = "alarm_period deve ser um múltiplo de 60, a partir de 60."
  }
}

variable "alarm_evaluation_periods" {
  description = "Número de períodos avaliados pelos alarmes."
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && floor(var.alarm_evaluation_periods) == var.alarm_evaluation_periods
    error_message = "alarm_evaluation_periods deve ser um inteiro maior ou igual a 1."
  }
}

variable "elb_5xx_alarm_threshold" {
  description = "Respostas 5xx geradas pelo próprio ALB (ex.: 502/503 sem alvo saudável) no período a partir das quais o alarme <name>-elb-5xx dispara."
  type        = number
  default     = 10

  validation {
    condition     = var.elb_5xx_alarm_threshold >= 1
    error_message = "elb_5xx_alarm_threshold deve ser maior ou igual a 1."
  }
}

variable "target_5xx_alarm_threshold" {
  description = "Respostas 5xx dos alvos no período a partir das quais o alarme <name>-target-5xx dispara."
  type        = number
  default     = 10

  validation {
    condition     = var.target_5xx_alarm_threshold >= 1
    error_message = "target_5xx_alarm_threshold deve ser maior ou igual a 1."
  }
}

variable "latency_alarm_threshold" {
  description = "p95 do TargetResponseTime, em segundos, acima do qual o alarme <name>-latency dispara."
  type        = number
  default     = 2

  validation {
    condition     = var.latency_alarm_threshold > 0
    error_message = "latency_alarm_threshold deve ser maior que 0."
  }
}

variable "alarm_actions" {
  description = "ARNs acionados quando um alarme entra em ALARM (ex.: tópico SNS). Aplicadas a todos os alarmes do módulo."
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "ARNs acionados quando um alarme volta para OK. Aplicadas a todos os alarmes do módulo."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos que aceitam tags."
  type        = map(string)
  default     = {}
}
