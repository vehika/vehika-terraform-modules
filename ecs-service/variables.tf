variable "name" {
  description = "Nome do serviço ECS. Também é a família da task definition, o nome do security group, o prefixo das roles (<name>-task e <name>-execution) e dos alarmes, e define o log group padrão (/ecs/<name>)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,54}$", var.name))
    error_message = "name deve ter de 1 a 54 caracteres: letras, números, - e _."
  }
}

variable "cluster_arn" {
  description = "ARN do cluster ECS onde o serviço roda. O cluster precisa ter os capacity providers usados em capacity_provider_strategy (FARGATE e/ou FARGATE_SPOT)."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:ecs:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9_-]{1,255}$", var.cluster_arn))
    error_message = "cluster_arn deve ser o ARN de um cluster ECS (arn:<partição>:ecs:<região>:<conta>:cluster/<nome>)."
  }
}

variable "vpc_id" {
  description = "ID da VPC do security group do serviço."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets das tarefas. Sem NAT, use as subnets públicas com assign_public_ip = true."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "Informe pelo menos uma subnet."
  }
}

variable "assign_public_ip" {
  description = "Atribui IP público às tarefas. Necessário em subnet pública sem NAT para alcançar o ECR, o SSM e APIs externas. A entrada continua limitada pelo security group."
  type        = bool
  default     = false
}

variable "container_image" {
  description = "Imagem do contêiner (ex.: <registro>/<repositório>@sha256:<digest> ou :<tag>). Prefira digest para deploys reproduzíveis."
  type        = string

  validation {
    condition     = length(var.container_image) > 0
    error_message = "container_image não pode ser vazio."
  }
}

variable "container_name" {
  description = "Nome do contêiner na task definition (usado pelo target group)."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,255}$", var.container_name))
    error_message = "container_name deve ter de 1 a 255 caracteres: letras, números, - e _."
  }
}

variable "container_port" {
  description = "Porta TCP exposta pelo contêiner. Nulo (padrão) não expõe porta (ex.: worker), e então não há entrada no security group nem target group."
  type        = number
  default     = null

  validation {
    condition     = var.container_port == null || (coalesce(var.container_port, 1) >= 1 && coalesce(var.container_port, 1) <= 65535 && floor(coalesce(var.container_port, 1)) == coalesce(var.container_port, 1))
    error_message = "container_port deve ser um inteiro entre 1 e 65535."
  }
}

variable "cpu" {
  description = "CPU da tarefa em unidades de vCPU (256 = 0,25 vCPU). Valores do Fargate: 256, 512, 1024, 2048, 4096, 8192 ou 16384."
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu deve ser 256, 512, 1024, 2048, 4096, 8192 ou 16384."
  }
}

variable "memory" {
  description = "Memória da tarefa, em MiB, numa combinação aceita pelo Fargate para a cpu escolhida (ex.: 256 => 512, 1024 ou 2048)."
  type        = number
  default     = 512

  validation {
    condition = (
      var.cpu == 256 ? contains([512, 1024, 2048], var.memory) :
      var.cpu == 512 ? var.memory >= 1024 && var.memory <= 4096 && var.memory % 1024 == 0 :
      var.cpu == 1024 ? var.memory >= 2048 && var.memory <= 8192 && var.memory % 1024 == 0 :
      var.cpu == 2048 ? var.memory >= 4096 && var.memory <= 16384 && var.memory % 1024 == 0 :
      var.cpu == 4096 ? var.memory >= 8192 && var.memory <= 30720 && var.memory % 1024 == 0 :
      var.cpu == 8192 ? var.memory >= 16384 && var.memory <= 61440 && var.memory % 4096 == 0 :
      var.memory >= 32768 && var.memory <= 122880 && var.memory % 8192 == 0
    )
    error_message = "memory não é uma combinação válida do Fargate para a cpu escolhida."
  }
}

variable "cpu_architecture" {
  description = "Arquitetura da tarefa: ARM64 (padrão, Graviton) ou X86_64. A imagem precisa ser da mesma arquitetura."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture deve ser ARM64 ou X86_64."
  }
}

variable "command" {
  description = "Comando do contêiner (substitui o CMD da imagem). Nulo (padrão) usa o da imagem."
  type        = list(string)
  default     = null
}

variable "entry_point" {
  description = "Entrypoint do contêiner (substitui o ENTRYPOINT da imagem). Nulo (padrão) usa o da imagem."
  type        = list(string)
  default     = null
}

variable "environment" {
  description = "Variáveis de ambiente do contêiner. Nunca coloque segredos aqui: elas aparecem no estado, no plan e na task definition. Use secrets."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for env_name in keys(var.environment) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", env_name))])
    error_message = "Os nomes das variáveis de ambiente devem começar com letra ou _ e conter só letras, números e _."
  }
}

variable "secrets" {
  description = "Segredos injetados como variáveis de ambiente pelo ECS, sem valor no Terraform: chave = nome da variável, valor = nome do parâmetro SSM (ex.: /<org>/<env>/<serviço>/database-url), ARN do parâmetro SSM ou ARN de um segredo do Secrets Manager (aceita o sufixo :<chave-json>:<estágio>:<versão>). A role de execução recebe leitura só nesses ARNs."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for env_name in keys(var.secrets) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", env_name))])
    error_message = "Os nomes das variáveis de secrets devem começar com letra ou _ e conter só letras, números e _."
  }

  validation {
    condition = alltrue([for value_from in values(var.secrets) : (
      can(regex("^/?[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", value_from)) ||
      can(regex("^arn:aws[a-z-]*:ssm:[a-z0-9-]+:[0-9]{12}:parameter/.+$", value_from)) ||
      can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", value_from))
    )])
    error_message = "Cada valor de secrets deve ser o nome de um parâmetro SSM, o ARN de um parâmetro SSM ou o ARN de um segredo do Secrets Manager."
  }

  validation {
    condition     = length(setintersection(keys(var.secrets), keys(var.environment))) == 0
    error_message = "Uma variável não pode estar em environment e em secrets ao mesmo tempo."
  }
}

variable "secrets_kms_key_arns" {
  description = "ARNs das CMKs que criptografam os parâmetros SecureString ou segredos de secrets. A role de execução recebe kms:Decrypt só nelas. Vazio (padrão) basta para as chaves gerenciadas aws/ssm e aws/secretsmanager."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for key_arn in var.secrets_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:", key_arn))])
    error_message = "Cada item de secrets_kms_key_arns deve ser o ARN de uma chave KMS (arn:<partição>:kms:...)."
  }
}

variable "ecr_repository_arns" {
  description = "ARNs dos repositórios ECR de onde a imagem é puxada. A role de execução recebe pull só neles (mais ecr:GetAuthorizationToken, que não aceita escopo). Vazio (padrão) não concede acesso ao ECR (imagem pública)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for repository_arn in var.ecr_repository_arns : can(regex("^arn:aws[a-z-]*:ecr:[a-z0-9-]+:[0-9]{12}:repository/.+$", repository_arn))])
    error_message = "Cada item de ecr_repository_arns deve ser o ARN de um repositório ECR."
  }
}

variable "role_path" {
  description = "Caminho IAM das roles de tarefa e de execução, começando e terminando com / (ex.: /<org>/<env>/)."
  type        = string

  validation {
    condition     = can(regex("^/([A-Za-z0-9_+=,.@-]+/)*$", var.role_path))
    error_message = "O caminho IAM deve começar e terminar com /."
  }
}

variable "permissions_boundary_arn" {
  description = "ARN da política usada como permissions boundary das roles de tarefa e de execução. Obrigatório, sem padrão."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-[a-z]+)*:iam::([0-9]{12}|aws):policy/[A-Za-z0-9_+=,.@/-]+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn deve ser o ARN de uma política IAM (arn:<partição>:iam::<conta>:policy/<nome>)."
  }
}

variable "task_role_name" {
  description = "Nome da role da tarefa (usada pela aplicação). Nulo (padrão) usa <name>-task."
  type        = string
  default     = null

  validation {
    condition     = var.task_role_name == null || can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", coalesce(var.task_role_name, "-")))
    error_message = "O nome da role deve ter de 1 a 64 caracteres: letras, números e _+=,.@-."
  }
}

variable "execution_role_name" {
  description = "Nome da role de execução (usada pelo ECS para puxar a imagem, ler segredos e escrever logs). Nulo (padrão) usa <name>-execution."
  type        = string
  default     = null

  validation {
    condition     = var.execution_role_name == null || can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", coalesce(var.execution_role_name, "-")))
    error_message = "O nome da role deve ter de 1 a 64 caracteres: letras, números e _+=,.@-."
  }
}

variable "task_role_policies" {
  description = "Políticas inline da role da tarefa (ex.: filas, bucket): chave = nome da política, valor = documento JSON. O documento pode ser conhecido só no apply; as chaves precisam ser conhecidas no plan. Vazio (padrão) deixa a role sem permissões."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for policy_name in keys(var.task_role_policies) : can(regex("^[A-Za-z0-9_+=,.@-]{1,128}$", policy_name)) && policy_name != "ecs-exec"])
    error_message = "Os nomes das políticas devem ter de 1 a 128 caracteres (letras, números e _+=,.@-) e não podem ser ecs-exec, reservado pelo módulo."
  }

  validation {
    condition     = alltrue([for policy in values(var.task_role_policies) : can(jsondecode(policy))])
    error_message = "Cada política deve ser um documento JSON válido."
  }
}

variable "log_group_name" {
  description = "Nome do log group do contêiner. Nulo (padrão) usa /ecs/<name>."
  type        = string
  default     = null

  validation {
    condition     = var.log_group_name == null || can(regex("^[A-Za-z0-9_./#-]{1,512}$", coalesce(var.log_group_name, "-")))
    error_message = "log_group_name deve ter de 1 a 512 caracteres: letras, números e _./#-."
  }
}

variable "log_retention_in_days" {
  description = "Retenção do log group, em dias. Aceita os valores do CloudWatch Logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days deve ser um dos valores aceitos pelo CloudWatch Logs: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 ou 3653."
  }
}

variable "log_group_kms_key_arn" {
  description = "ARN de uma CMK para o log group. Nulo (padrão) usa a criptografia gerenciada pelo CloudWatch Logs."
  type        = string
  default     = null

  validation {
    condition     = var.log_group_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", coalesce(var.log_group_kms_key_arn, "-")))
    error_message = "log_group_kms_key_arn deve ser o ARN de uma chave KMS (arn:<partição>:kms:...)."
  }
}

variable "desired_count" {
  description = "Número de tarefas na criação do serviço. Depois da criação, o módulo ignora mudanças nele (quem ajusta é o autoscaling); para mudar a contagem sem autoscaling, use autoscaling_min_capacity = autoscaling_max_capacity."
  type        = number
  default     = 1

  validation {
    condition     = var.desired_count >= 0 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count deve ser um inteiro maior ou igual a 0."
  }
}

variable "capacity_provider_strategy" {
  description = "Estratégia de capacity providers: FARGATE (padrão) e/ou FARGATE_SPOT, com weight e base. Ex.: [{ capacity_provider = \"FARGATE_SPOT\" }] para um worker interrompível."
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default = [{ capacity_provider = "FARGATE" }]

  validation {
    condition     = length(var.capacity_provider_strategy) >= 1 && alltrue([for strategy in var.capacity_provider_strategy : contains(["FARGATE", "FARGATE_SPOT"], strategy.capacity_provider) && strategy.weight >= 0 && strategy.base >= 0])
    error_message = "capacity_provider_strategy precisa de pelo menos um item com FARGATE ou FARGATE_SPOT, weight e base maiores ou iguais a 0."
  }

  validation {
    condition     = length(distinct([for strategy in var.capacity_provider_strategy : strategy.capacity_provider])) == length(var.capacity_provider_strategy)
    error_message = "Cada capacity provider deve aparecer uma vez só."
  }
}

variable "deployment_minimum_healthy_percent" {
  description = "Percentual mínimo de tarefas saudáveis durante o deploy."
  type        = number
  default     = 100

  validation {
    condition     = var.deployment_minimum_healthy_percent >= 0 && var.deployment_minimum_healthy_percent <= 100
    error_message = "deployment_minimum_healthy_percent deve estar entre 0 e 100."
  }
}

variable "deployment_maximum_percent" {
  description = "Percentual máximo de tarefas durante o deploy."
  type        = number
  default     = 200

  validation {
    condition     = var.deployment_maximum_percent >= 100 && var.deployment_maximum_percent <= 200
    error_message = "deployment_maximum_percent deve estar entre 100 e 200."
  }
}

variable "target_group_arn" {
  description = "ARN do target group (tipo ip) que recebe o tráfego do contêiner. Nulo (padrão) não registra o serviço em load balancer. Exige container_port."
  type        = string
  default     = null

  validation {
    condition     = var.target_group_arn == null || var.container_port != null
    error_message = "target_group_arn exige container_port."
  }
}

variable "health_check_grace_period_seconds" {
  description = "Tempo, em segundos, em que o ECS ignora health checks do load balancer depois que a tarefa sobe. Só vale com target_group_arn."
  type        = number
  default     = 60

  validation {
    condition     = var.health_check_grace_period_seconds >= 0 && var.health_check_grace_period_seconds <= 2147483647
    error_message = "health_check_grace_period_seconds deve ser maior ou igual a 0."
  }
}

variable "allowed_security_groups" {
  description = "Security groups que podem abrir conexão na container_port (ex.: o do ALB): chave = nome lógico da regra (conhecido no plan), valor = ID do security group. Exige container_port. Não há entrada de CIDRs."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for rule_name in keys(var.allowed_security_groups) : can(regex("^[A-Za-z0-9_-]{1,64}$", rule_name))])
    error_message = "As chaves de allowed_security_groups devem ter de 1 a 64 caracteres: letras, números, _ e -."
  }

  validation {
    condition     = length(var.allowed_security_groups) == 0 || var.container_port != null
    error_message = "allowed_security_groups exige container_port."
  }
}

variable "egress_rules" {
  description = "Regras de saída do security group: chave = nome lógico (conhecido no plan). Cada regra tem exatamente um destino: cidr_ipv4, referenced_security_group_id ou prefix_list_id. O padrão libera só HTTPS para a internet (ECR, SSM, Secrets Manager, CloudWatch Logs e APIs externas). Acrescente, por exemplo, a porta do banco para o security group do RDS."
  type = map(object({
    description                  = string
    ip_protocol                  = string
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    referenced_security_group_id = optional(string)
    prefix_list_id               = optional(string)
  }))
  default = {
    https = {
      description = "HTTPS para a internet (ECR, SSM, logs e APIs externas)"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  validation {
    condition     = alltrue([for rule_name in keys(var.egress_rules) : can(regex("^[A-Za-z0-9_-]{1,64}$", rule_name))])
    error_message = "As chaves de egress_rules devem ter de 1 a 64 caracteres: letras, números, _ e -."
  }

  validation {
    condition     = alltrue([for rule in values(var.egress_rules) : length([for destination in [rule.cidr_ipv4, rule.referenced_security_group_id, rule.prefix_list_id] : destination if destination != null]) == 1])
    error_message = "Cada regra de saída deve ter exatamente um destino: cidr_ipv4, referenced_security_group_id ou prefix_list_id."
  }

  validation {
    condition     = alltrue([for rule in values(var.egress_rules) : contains(["tcp", "udp", "icmp", "-1"], rule.ip_protocol)])
    error_message = "ip_protocol deve ser tcp, udp, icmp ou -1."
  }
}

variable "additional_security_group_ids" {
  description = "Security groups extras associados às tarefas, além do criado pelo módulo."
  type        = list(string)
  default     = []
}

variable "enable_execute_command" {
  description = "Habilita o ECS Exec (shell nas tarefas pelo SSM). Acrescenta à role da tarefa as ações ssmmessages, que não aceitam escopo por recurso."
  type        = bool
  default     = false
}

variable "readonly_root_filesystem" {
  description = "Monta o sistema de arquivos raiz do contêiner só para leitura. Recomendado quando a aplicação não grava fora de volumes."
  type        = bool
  default     = false
}

variable "health_check" {
  description = "Health check do contêiner. Nulo (padrão) não define health check no contêiner (o do target group continua valendo). command segue o formato do ECS (ex.: [\"CMD-SHELL\", \"curl -f http://localhost:3000/health || exit 1\"])."
  type = object({
    command      = list(string)
    interval     = optional(number, 30)
    timeout      = optional(number, 5)
    retries      = optional(number, 3)
    start_period = optional(number, 0)
  })
  default = null
}

variable "stop_timeout" {
  description = "Segundos entre o SIGTERM e o SIGKILL do contêiner (2 a 120). No Fargate Spot o aviso de interrupção é de 2 minutos."
  type        = number
  default     = 30

  validation {
    condition     = var.stop_timeout >= 2 && var.stop_timeout <= 120 && floor(var.stop_timeout) == var.stop_timeout
    error_message = "stop_timeout deve ser um inteiro entre 2 e 120."
  }
}

variable "wait_for_steady_state" {
  description = "Faz o apply esperar o serviço estabilizar. Com o circuit breaker, um deploy revertido falha o apply."
  type        = bool
  default     = false
}

variable "autoscaling_max_capacity" {
  description = "Máximo de tarefas do autoscaling por CPU. Nulo (padrão) não cria autoscaling."
  type        = number
  default     = null

  validation {
    condition     = var.autoscaling_max_capacity == null || (coalesce(var.autoscaling_max_capacity, 1) >= 1 && floor(coalesce(var.autoscaling_max_capacity, 1)) == coalesce(var.autoscaling_max_capacity, 1))
    error_message = "autoscaling_max_capacity deve ser um inteiro maior ou igual a 1."
  }
}

variable "autoscaling_min_capacity" {
  description = "Mínimo de tarefas do autoscaling. Nulo (padrão) usa desired_count."
  type        = number
  default     = null

  validation {
    condition     = var.autoscaling_min_capacity == null || (coalesce(var.autoscaling_min_capacity, 0) >= 0 && floor(coalesce(var.autoscaling_min_capacity, 0)) == coalesce(var.autoscaling_min_capacity, 0))
    error_message = "autoscaling_min_capacity deve ser um inteiro maior ou igual a 0."
  }

  validation {
    condition     = var.autoscaling_max_capacity == null || coalesce(var.autoscaling_min_capacity, var.desired_count) <= coalesce(var.autoscaling_max_capacity, 0)
    error_message = "O mínimo do autoscaling (autoscaling_min_capacity ou desired_count) não pode passar de autoscaling_max_capacity."
  }
}

variable "autoscaling_cpu_target" {
  description = "CPU média do serviço, em %, que o autoscaling tenta manter."
  type        = number
  default     = 70

  validation {
    condition     = var.autoscaling_cpu_target >= 10 && var.autoscaling_cpu_target <= 90
    error_message = "autoscaling_cpu_target deve estar entre 10 e 90."
  }
}

variable "autoscaling_scale_in_cooldown" {
  description = "Espera, em segundos, depois de reduzir tarefas."
  type        = number
  default     = 300

  validation {
    condition     = var.autoscaling_scale_in_cooldown >= 0
    error_message = "autoscaling_scale_in_cooldown deve ser maior ou igual a 0."
  }
}

variable "autoscaling_scale_out_cooldown" {
  description = "Espera, em segundos, depois de acrescentar tarefas."
  type        = number
  default     = 60

  validation {
    condition     = var.autoscaling_scale_out_cooldown >= 0
    error_message = "autoscaling_scale_out_cooldown deve ser maior ou igual a 0."
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
  description = "CPU média do serviço, em %, acima da qual o alarme <name>-cpu dispara."
  type        = number
  default     = 85

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold deve estar entre 0 (exclusivo) e 100."
  }
}

variable "memory_alarm_threshold" {
  description = "Memória média do serviço, em %, acima da qual o alarme <name>-memory dispara."
  type        = number
  default     = 85

  validation {
    condition     = var.memory_alarm_threshold > 0 && var.memory_alarm_threshold <= 100
    error_message = "memory_alarm_threshold deve estar entre 0 (exclusivo) e 100."
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
