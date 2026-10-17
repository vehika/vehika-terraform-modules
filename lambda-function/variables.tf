variable "name" {
  description = "Nome da função Lambda. Também define o log group (/aws/lambda/<name>), o alarme (<name>-errors) e, por padrão, o nome da role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,64}$", var.name))
    error_message = "O nome da função deve ter de 1 a 64 caracteres: letras, números, - e _."
  }
}

variable "description" {
  description = "Descrição da função Lambda."
  type        = string
  default     = ""
}

variable "filename" {
  description = "Caminho local do pacote .zip enviado direto para o Lambda (sem S3). Limite do upload direto: 50 MB compactado."
  type        = string
}

variable "source_code_hash" {
  description = "Hash base64 SHA-256 do pacote (ex.: filebase64sha256(var.filename)). Uma mudança no hash publica o código novo."
  type        = string
}

variable "handler" {
  description = "Ponto de entrada da função (ex.: index.handler)."
  type        = string
}

variable "runtime" {
  description = "Runtime da função."
  type        = string
  default     = "nodejs24.x"
}

variable "architectures" {
  description = "Arquitetura da função: [\"arm64\"] ou [\"x86_64\"]."
  type        = list(string)
  default     = ["arm64"]

  validation {
    condition     = length(var.architectures) == 1 && alltrue([for architecture in var.architectures : contains(["arm64", "x86_64"], architecture)])
    error_message = "Informe exatamente uma arquitetura: arm64 ou x86_64."
  }
}

variable "memory_size" {
  description = "Memória da função, em MB (128 a 10240)."
  type        = number
  default     = 256

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240 && floor(var.memory_size) == var.memory_size
    error_message = "memory_size deve ser um inteiro entre 128 e 10240."
  }
}

variable "timeout" {
  description = "Tempo máximo de execução, em segundos (1 a 900)."
  type        = number
  default     = 10

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900 && floor(var.timeout) == var.timeout
    error_message = "timeout deve ser um inteiro entre 1 e 900."
  }
}

variable "reserved_concurrent_executions" {
  description = "Concorrência reservada; 0 impede qualquer execução. A AWS mantém pelo menos 100 de concorrência não reservada na conta; com cota menor (contas novas podem ter 10), qualquer reserva falha. Por isso o padrão é -1 (sem reserva)."
  type        = number
  default     = -1

  validation {
    condition     = var.reserved_concurrent_executions >= -1 && floor(var.reserved_concurrent_executions) == var.reserved_concurrent_executions
    error_message = "reserved_concurrent_executions deve ser um inteiro maior ou igual a -1."
  }
}

variable "environment_variables" {
  description = "Variáveis de ambiente da função. Nunca coloque segredos aqui: elas aparecem no estado, no plan e para quem lê a configuração da função."
  type        = map(string)
  default     = {}
}

variable "tracing_mode" {
  description = "Modo de rastreamento do X-Ray: Active ou PassThrough."
  type        = string
  default     = "Active"

  validation {
    condition     = contains(["Active", "PassThrough"], var.tracing_mode)
    error_message = "tracing_mode deve ser Active ou PassThrough."
  }
}

variable "log_format" {
  description = "Formato dos logs da função: JSON ou Text."
  type        = string
  default     = "JSON"

  validation {
    condition     = contains(["JSON", "Text"], var.log_format)
    error_message = "log_format deve ser JSON ou Text."
  }
}

variable "log_retention_in_days" {
  description = "Retenção do log group, em dias. Aceita os valores do CloudWatch Logs (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days deve ser um dos valores aceitos pelo CloudWatch Logs: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 ou 3653."
  }
}

variable "log_group_kms_key_arn" {
  description = "ARN de uma chave KMS para criptografar o log group. Nulo (padrão) usa a criptografia gerenciada pelo CloudWatch Logs. A key policy precisa permitir o serviço logs da região."
  type        = string
  default     = null

  validation {
    condition     = var.log_group_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.log_group_kms_key_arn))
    error_message = "log_group_kms_key_arn deve ser o ARN de uma chave KMS (arn:<partição>:kms:...)."
  }
}

variable "role_name" {
  description = "Nome da role de execução. Nulo (padrão) usa o nome da função."
  type        = string
  default     = null

  validation {
    condition     = var.role_name == null || can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.role_name))
    error_message = "O nome da role deve ter de 1 a 64 caracteres: letras, números e _+=,.@-."
  }
}

variable "role_path" {
  description = "Caminho IAM da role de execução, começando e terminando com / (ex.: /<org>/<env>/)."
  type        = string

  validation {
    condition     = can(regex("^/([A-Za-z0-9_+=,.@-]+/)*$", var.role_path))
    error_message = "O caminho IAM deve começar e terminar com /."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN da política usada como permissions boundary da role de execução. Obrigatório."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:iam::([0-9]{12}|aws):policy/[A-Za-z0-9_+=,.@/-]+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn deve ser o ARN de uma política IAM (arn:<partição>:iam::<conta>:policy/<nome>)."
  }
}

variable "additional_policies" {
  description = "Políticas inline adicionais da role (ex.: acesso a filas ou tabelas): chave = nome da política, valor = documento JSON. O documento pode ser conhecido só no apply; as chaves precisam ser conhecidas no plan. Vazio (padrão) não cria nenhuma."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for policy_name in keys(var.additional_policies) : can(regex("^[A-Za-z0-9_+=,.@-]{1,128}$", policy_name)) && policy_name != "base"])
    error_message = "Os nomes das políticas adicionais devem ter de 1 a 128 caracteres (letras, números e _+=,.@-) e não podem ser base, que é a política do módulo."
  }

  validation {
    condition     = alltrue([for policy in values(var.additional_policies) : can(jsondecode(policy))])
    error_message = "Cada política adicional deve ser um documento JSON válido."
  }
}

variable "error_alarm_period" {
  description = "Período do alarme de erros, em segundos (múltiplo de 60)."
  type        = number
  default     = 300

  validation {
    condition     = var.error_alarm_period >= 60 && var.error_alarm_period % 60 == 0
    error_message = "error_alarm_period deve ser um múltiplo de 60, a partir de 60."
  }
}

variable "error_alarm_evaluation_periods" {
  description = "Número de períodos avaliados pelo alarme de erros."
  type        = number
  default     = 1

  validation {
    condition     = var.error_alarm_evaluation_periods >= 1 && floor(var.error_alarm_evaluation_periods) == var.error_alarm_evaluation_periods
    error_message = "error_alarm_evaluation_periods deve ser um inteiro maior ou igual a 1."
  }
}

variable "error_alarm_threshold" {
  description = "Soma de erros no período a partir da qual o alarme dispara (GreaterThanOrEqualToThreshold)."
  type        = number
  default     = 1

  validation {
    condition     = var.error_alarm_threshold >= 1
    error_message = "error_alarm_threshold deve ser maior ou igual a 1."
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
