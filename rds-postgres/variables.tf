variable "identifier" {
  description = "Identificador da instância RDS. Também nomeia o security group, o subnet group, o parameter group (<identifier>-<família>) e os alarmes (<identifier>-<métrica>)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,52}$", var.identifier)) && !strcontains(var.identifier, "--") && !endswith(var.identifier, "-")
    error_message = "identifier deve ter de 1 a 53 caracteres minúsculos (letras, números e -), começar com letra, sem -- e sem terminar em -."
  }
}

variable "engine_version" {
  description = "Versão do PostgreSQL. Só o major (ex.: \"17\") deixa a AWS escolher o minor padrão e aceita as atualizações automáticas de minor sem diff. A família do parameter group sai do major (postgres<major>)."
  type        = string
  default     = "17"

  validation {
    condition     = can(regex("^[0-9]{2}(\\.[0-9]+)?$", var.engine_version))
    error_message = "engine_version deve ser <major> ou <major>.<minor> (ex.: 17 ou 17.6)."
  }
}

variable "engine_lifecycle_support" {
  description = "Suporte estendido pago do RDS depois do fim do suporte padrão do major: open-source-rds-extended-support-disabled (padrão, sem cobrança; a AWS atualiza o major no fim do suporte) ou open-source-rds-extended-support."
  type        = string
  default     = "open-source-rds-extended-support-disabled"

  validation {
    condition     = contains(["open-source-rds-extended-support", "open-source-rds-extended-support-disabled"], var.engine_lifecycle_support)
    error_message = "engine_lifecycle_support deve ser open-source-rds-extended-support ou open-source-rds-extended-support-disabled."
  }
}

variable "instance_class" {
  description = "Classe da instância."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = can(regex("^db\\.[a-z0-9-]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class deve ser uma classe RDS (ex.: db.t4g.micro)."
  }
}

variable "allocated_storage" {
  description = "Armazenamento gp3 inicial, em GiB (mínimo 20)."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 65536 && floor(var.allocated_storage) == var.allocated_storage
    error_message = "allocated_storage deve ser um inteiro entre 20 e 65536."
  }
}

variable "max_allocated_storage" {
  description = "Teto do autoscaling de armazenamento, em GiB. Deve ser maior que allocated_storage; 0 desliga o autoscaling."
  type        = number
  default     = 100

  validation {
    condition     = floor(var.max_allocated_storage) == var.max_allocated_storage && (var.max_allocated_storage == 0 || (var.max_allocated_storage > var.allocated_storage && var.max_allocated_storage <= 65536))
    error_message = "max_allocated_storage deve ser 0 ou um inteiro maior que allocated_storage (até 65536)."
  }
}

variable "kms_key_arn" {
  description = "ARN da CMK que criptografa o armazenamento, os snapshots e os backups automáticos. Nulo (padrão) usa a chave gerenciada aws/rds. Trocar a chave recria a instância."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", coalesce(var.kms_key_arn, "-")))
    error_message = "kms_key_arn deve ser o ARN de uma chave KMS (arn:<partição>:kms:...)."
  }
}

variable "db_name" {
  description = "Nome do banco criado com a instância. Nulo (padrão) não cria banco além do postgres."
  type        = string
  default     = null

  validation {
    condition     = var.db_name == null || can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", coalesce(var.db_name, "-")))
    error_message = "db_name deve começar com letra e ter até 63 caracteres: letras, números e _."
  }
}

variable "master_username" {
  description = "Usuário master. A senha é gerada e guardada pelo RDS no Secrets Manager (manage_master_user_password); nunca passa pelo Terraform."
  type        = string
  default     = "postgres"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.master_username)) && !contains(["rdsadmin", "rdsrepladmin", "rds_superuser"], lower(var.master_username))
    error_message = "master_username deve começar com letra, ter até 63 caracteres (letras, números e _) e não pode ser um nome reservado do RDS."
  }
}

variable "master_user_secret_kms_key_arn" {
  description = "ARN da CMK que criptografa o segredo da senha master no Secrets Manager. Nulo (padrão) usa a chave aws/secretsmanager."
  type        = string
  default     = null

  validation {
    condition     = var.master_user_secret_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", coalesce(var.master_user_secret_kms_key_arn, "-")))
    error_message = "master_user_secret_kms_key_arn deve ser o ARN de uma chave KMS (arn:<partição>:kms:...)."
  }
}

variable "port" {
  description = "Porta do PostgreSQL."
  type        = number
  default     = 5432

  validation {
    condition     = var.port >= 1150 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port deve ser um inteiro entre 1150 e 65535."
  }
}

variable "vpc_id" {
  description = "ID da VPC do security group da instância."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets do subnet group (normalmente as privadas), em pelo menos duas zonas."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Informe pelo menos duas subnets, em zonas diferentes."
  }
}

variable "allowed_security_groups" {
  description = "Security groups que podem abrir conexão na porta do banco: chave = nome lógico da regra (conhecido no plan), valor = ID do security group (pode ser conhecido só no apply). Vazio (padrão) não libera ninguém."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for rule_name in keys(var.allowed_security_groups) : can(regex("^[A-Za-z0-9_-]{1,64}$", rule_name))])
    error_message = "As chaves de allowed_security_groups devem ter de 1 a 64 caracteres: letras, números, _ e -."
  }
}

variable "additional_security_group_ids" {
  description = "Security groups extras associados à instância, além do criado pelo módulo."
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "Dá endereço público à instância. Padrão false; true exige subnets públicas e ainda depende do security group."
  type        = bool
  default     = false
}

variable "multi_az" {
  description = "Instância Multi-AZ (standby síncrono em outra zona). Dobra o custo da instância e do armazenamento."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Retenção dos backups automáticos e da janela de point-in-time recovery, em dias (1 a 35). O módulo não permite 0, que desligaria o PITR."
  type        = number
  default     = 14

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "backup_retention_period deve ser um inteiro entre 1 e 35."
  }
}

variable "backup_window" {
  description = "Janela diária do backup automático, em UTC (ex.: 06:00-06:30). Nulo (padrão) deixa a AWS escolher."
  type        = string
  default     = null

  validation {
    condition     = var.backup_window == null || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", coalesce(var.backup_window, "-")))
    error_message = "backup_window deve estar no formato hh24:mi-hh24:mi."
  }
}

variable "maintenance_window" {
  description = "Janela semanal de manutenção, em UTC (ex.: sun:07:00-sun:08:00). Nulo (padrão) deixa a AWS escolher."
  type        = string
  default     = null

  validation {
    condition     = var.maintenance_window == null || can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]$", coalesce(var.maintenance_window, "-")))
    error_message = "maintenance_window deve estar no formato ddd:hh24:mi-ddd:hh24:mi."
  }
}

variable "deletion_protection" {
  description = "Impede apagar a instância. Para destruir, desligue antes num apply separado."
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Nome do snapshot final tirado ao apagar a instância. Nulo (padrão) usa <identifier>-final. O módulo sempre tira o snapshot final."
  type        = string
  default     = null

  validation {
    condition     = var.final_snapshot_identifier == null || can(regex("^[A-Za-z][A-Za-z0-9-]{0,254}$", coalesce(var.final_snapshot_identifier, "-")))
    error_message = "final_snapshot_identifier deve começar com letra e ter até 255 caracteres: letras, números e -."
  }
}

variable "apply_immediately" {
  description = "Aplica mudanças da instância na hora, em vez de esperar a janela de manutenção. Algumas mudanças reiniciam a instância."
  type        = bool
  default     = false
}

variable "auto_minor_version_upgrade" {
  description = "Atualiza o minor do PostgreSQL automaticamente na janela de manutenção."
  type        = bool
  default     = true
}

variable "ca_cert_identifier" {
  description = "Certificado da CA do RDS usado pelo TLS do servidor."
  type        = string
  default     = "rds-ca-rsa2048-g1"
}

variable "iam_database_authentication_enabled" {
  description = "Habilita a autenticação no banco por IAM."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Habilita o Performance Insights. Desligado por padrão (custo e suporte limitado em classes pequenas)."
  type        = bool
  default     = false
}

variable "performance_insights_kms_key_arn" {
  description = "ARN da CMK do Performance Insights. Nulo usa a chave aws/rds."
  type        = string
  default     = null

  validation {
    condition     = var.performance_insights_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", coalesce(var.performance_insights_kms_key_arn, "-")))
    error_message = "performance_insights_kms_key_arn deve ser o ARN de uma chave KMS (arn:<partição>:kms:...)."
  }
}

variable "enabled_cloudwatch_logs_exports" {
  description = "Logs exportados para o CloudWatch Logs: postgresql, upgrade e/ou iam-db-auth-error. O módulo cria os log groups /aws/rds/instance/<identifier>/<tipo> com retenção. Vazio (padrão) não exporta."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for log_type in var.enabled_cloudwatch_logs_exports : contains(["postgresql", "upgrade", "iam-db-auth-error"], log_type)])
    error_message = "enabled_cloudwatch_logs_exports aceita só postgresql, upgrade e iam-db-auth-error."
  }
}

variable "log_retention_in_days" {
  description = "Retenção dos log groups exportados, em dias. Aceita os valores do CloudWatch Logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days deve ser um dos valores aceitos pelo CloudWatch Logs: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 ou 3653."
  }
}

variable "log_group_kms_key_arn" {
  description = "ARN da CMK dos log groups exportados. Nulo (padrão) usa a criptografia gerenciada pelo CloudWatch Logs."
  type        = string
  default     = null

  validation {
    condition     = var.log_group_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", coalesce(var.log_group_kms_key_arn, "-")))
    error_message = "log_group_kms_key_arn deve ser o ARN de uma chave KMS (arn:<partição>:kms:...)."
  }
}

variable "parameters" {
  description = "Parâmetros extras do parameter group. rds.force_ssl é fixado em 1 pelo módulo e não pode ser sobrescrito. apply_method: immediate (padrão) ou pending-reboot (obrigatório para parâmetros estáticos)."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []

  validation {
    condition     = alltrue([for parameter in var.parameters : parameter.name != "rds.force_ssl" && contains(["immediate", "pending-reboot"], parameter.apply_method)])
    error_message = "parameters não pode incluir rds.force_ssl, e apply_method deve ser immediate ou pending-reboot."
  }

  validation {
    condition     = length(distinct([for parameter in var.parameters : parameter.name])) == length(var.parameters)
    error_message = "Cada parâmetro deve aparecer uma vez só."
  }
}

variable "backup_replication_enabled" {
  description = "Replica os backups automáticos (e o PITR) para outra região."
  type        = bool
  default     = false
}

variable "backup_replication_region" {
  description = "Região de destino da replicação dos backups (ex.: us-east-2). Obrigatória com backup_replication_enabled."
  type        = string
  default     = null

  validation {
    condition     = var.backup_replication_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]$", coalesce(var.backup_replication_region, "-")))
    error_message = "backup_replication_region deve ser um código de região (ex.: us-east-2)."
  }

  validation {
    condition     = !(var.backup_replication_enabled && var.backup_replication_region == null)
    error_message = "Com backup_replication_enabled, informe backup_replication_region."
  }
}

variable "backup_replication_kms_key_arn" {
  description = "ARN da chave KMS na região de destino que criptografa os backups replicados. Obrigatória com backup_replication_enabled (a instância é sempre criptografada)."
  type        = string
  default     = null

  validation {
    condition     = var.backup_replication_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", coalesce(var.backup_replication_kms_key_arn, "-")))
    error_message = "backup_replication_kms_key_arn deve ser o ARN de uma chave KMS (arn:<partição>:kms:...)."
  }

  validation {
    condition     = !(var.backup_replication_enabled && var.backup_replication_kms_key_arn == null)
    error_message = "Com backup_replication_enabled, informe backup_replication_kms_key_arn (chave da região de destino)."
  }

  validation {
    condition     = var.backup_replication_kms_key_arn == null || var.backup_replication_region == null || strcontains(coalesce(var.backup_replication_kms_key_arn, "-"), ":kms:${coalesce(var.backup_replication_region, "-")}:")
    error_message = "backup_replication_kms_key_arn deve ser uma chave da região backup_replication_region."
  }
}

variable "backup_replication_retention_period" {
  description = "Retenção dos backups replicados, em dias (1 a 35). Nulo (padrão) usa backup_retention_period."
  type        = number
  default     = null

  validation {
    condition     = var.backup_replication_retention_period == null || (coalesce(var.backup_replication_retention_period, 1) >= 1 && coalesce(var.backup_replication_retention_period, 1) <= 35 && floor(coalesce(var.backup_replication_retention_period, 1)) == coalesce(var.backup_replication_retention_period, 1))
    error_message = "backup_replication_retention_period deve ser um inteiro entre 1 e 35."
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
  default     = 3

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && floor(var.alarm_evaluation_periods) == var.alarm_evaluation_periods
    error_message = "alarm_evaluation_periods deve ser um inteiro maior ou igual a 1."
  }
}

variable "cpu_alarm_threshold" {
  description = "CPU média, em %, acima da qual o alarme <identifier>-cpu dispara."
  type        = number
  default     = 80

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold deve estar entre 0 (exclusivo) e 100."
  }
}

variable "freeable_memory_alarm_threshold" {
  description = "Memória livre, em bytes, abaixo da qual o alarme <identifier>-freeable-memory dispara. Padrão 100 MiB."
  type        = number
  default     = 104857600

  validation {
    condition     = var.freeable_memory_alarm_threshold > 0
    error_message = "freeable_memory_alarm_threshold deve ser maior que 0."
  }
}

variable "free_storage_alarm_threshold" {
  description = "Armazenamento livre, em bytes, abaixo do qual o alarme <identifier>-free-storage dispara. Padrão 2 GiB."
  type        = number
  default     = 2147483648

  validation {
    condition     = var.free_storage_alarm_threshold > 0
    error_message = "free_storage_alarm_threshold deve ser maior que 0."
  }
}

variable "connections_alarm_threshold" {
  description = "Conexões abertas acima das quais o alarme <identifier>-connections dispara. O max_connections padrão depende da memória da classe (cerca de 80 a 110 numa db.t4g.micro)."
  type        = number
  default     = 70

  validation {
    condition     = var.connections_alarm_threshold >= 1
    error_message = "connections_alarm_threshold deve ser maior ou igual a 1."
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
