# ecs-service

Serviço ECS no Fargate (ARM64 por padrão) com task definition de um contêiner, segredos do SSM ou do Secrets Manager por referência, Fargate ou Fargate Spot por capacity provider, circuit breaker com rollback, autoscaling por CPU opcional, log group próprio, roles com permissions boundary obrigatório e security group que só aceita entrada dos security groups informados (o ALB).

## O que cria

| Recurso | Nome | Detalhe |
| --- | --- | --- |
| `aws_cloudwatch_log_group` | `log_group_name` (padrão `/ecs/<name>`) | Retenção configurável (padrão 30 dias); CMK opcional. |
| `aws_iam_role` `execution` | `<name>-execution` | Usada pelo ECS. Caminho e boundary obrigatórios. Confia só em `ecs-tasks.amazonaws.com`. |
| `aws_iam_role_policy` `execution` | `execution` | Logs só nos streams do log group do módulo; pull só nos `ecr_repository_arns` (mais `ecr:GetAuthorizationToken`, sem escopo por recurso); `ssm:GetParameters` e `secretsmanager:GetSecretValue` só nos ARNs de `secrets`; `kms:Decrypt` só em `secrets_kms_key_arns`. Statements vazios não entram. |
| `aws_iam_role` `task` | `<name>-task` | Usada pela aplicação. Caminho e boundary obrigatórios. Confiança em `ecs-tasks.amazonaws.com` com `aws:SourceAccount` e `aws:SourceArn` da conta e região. Nasce sem permissões. |
| `aws_iam_role_policy` `task` | chave do mapa | Uma por item de `task_role_policies`. |
| `aws_iam_role_policy` `ecs_exec` | `ecs-exec` | Só com `enable_execute_command`: ações `ssmmessages` (sem escopo por recurso). |
| `aws_security_group` | `<name>-<sufixo>` | `name_prefix` com `create_before_destroy`. Entrada só na `container_port` e só dos `allowed_security_groups`; nenhuma entrada por CIDR. Saída por `egress_rules` (padrão: só TCP 443 para `0.0.0.0/0`). |
| `aws_ecs_task_definition` | família `<name>` | Fargate, `awsvpc`, `ARM64`/Linux, 256 CPU e 512 MiB, contêiner `app` essencial com `initProcessEnabled`, logs `awslogs`, variáveis ordenadas e segredos por `valueFrom`. |
| `aws_ecs_service` | `<name>` | Capacity provider strategy (padrão `FARGATE`), circuit breaker com rollback, `availability_zone_rebalancing`, tags propagadas do serviço, target group opcional. `desired_count` ignorado depois da criação. |
| `aws_appautoscaling_target` + `aws_appautoscaling_policy` | `<name>-cpu` | Só com `autoscaling_max_capacity`: target tracking de `ECSServiceAverageCPUUtilization` (alvo 70%). |
| `aws_cloudwatch_metric_alarm` | `<name>-cpu`, `<name>-memory` | `AWS/ECS` `CPUUtilization`/`MemoryUtilization` médias acima de 85% em 3 períodos de 300 s. |

O módulo **não cria o cluster**: ele recebe `cluster_arn`. O cluster precisa ter os capacity providers usados (`aws_ecs_cluster_capacity_providers` com `FARGATE` e `FARGATE_SPOT`); ver [`examples/ecs-service`](../examples/ecs-service). Sem `provider` declarado; exige Terraform `>= 1.11` e `hashicorp/aws` `>= 6.19, < 7.0`.

## Uso

API atrás do ALB, em subnet pública sem NAT:

```hcl
module "api" {
  source = "git::https://github.com/vehika/vehika-terraform-modules.git//ecs-service?ref=v0.2.0"

  name                     = "${local.name_prefix}-api"
  cluster_arn              = aws_ecs_cluster.this.arn
  vpc_id                   = module.network.vpc_id
  subnet_ids               = module.network.public_subnet_ids
  assign_public_ip         = true
  container_image          = "${aws_ecr_repository.app.repository_url}@${var.image_digest}"
  container_port           = 3000
  desired_count            = 2
  autoscaling_max_capacity = 4
  target_group_arn         = module.alb.target_group_arns["api"]
  allowed_security_groups  = { alb = module.alb.security_group_id }
  ecr_repository_arns      = [aws_ecr_repository.app.arn]
  log_group_name           = "/<org>/<env>/<serviço>/api"
  role_path                = data.aws_ssm_parameter.workload_path.insecure_value
  permissions_boundary_arn = data.aws_ssm_parameter.permissions_boundary_arn.insecure_value

  environment = { NODE_ENV = "production" }
  secrets = {
    DATABASE_URL = "/<org>/<env>/<serviço>/database-url"
  }

  egress_rules = {
    https    = { description = "HTTPS para a internet", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    postgres = { description = "PostgreSQL", ip_protocol = "tcp", from_port = 5432, to_port = 5432, referenced_security_group_id = module.database.security_group_id }
  }

  task_role_policies = {
    queue-access = data.aws_iam_policy_document.api_queues.json
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
```

Worker no Fargate Spot, sem porta: o mesmo módulo com `capacity_provider_strategy = [{ capacity_provider = "FARGATE_SPOT" }]`, sem `container_port`, `target_group_arn` e `allowed_security_groups`.

As **chaves** de `secrets`, `task_role_policies`, `allowed_security_groups` e `egress_rules` precisam ser conhecidas no plan (use nomes fixos); os valores podem vir de recursos da mesma stack.

## Variáveis

| Nome | Tipo | Padrão | Descrição |
| --- | --- | --- | --- |
| `name` | `string` | obrigatória | Nome do serviço (1 a 54 caracteres: letras, números, `-`, `_`). |
| `cluster_arn` | `string` | obrigatória | ARN do cluster ECS. |
| `vpc_id` | `string` | obrigatória | VPC do security group. |
| `subnet_ids` | `list(string)` | obrigatória | Subnets das tarefas. |
| `container_image` | `string` | obrigatória | Imagem (prefira digest). |
| `role_path` | `string` | obrigatória | Caminho IAM das roles (`/.../`). |
| `permissions_boundary_arn` | `string` | obrigatória | Boundary das duas roles. Sem padrão; vazio, nulo ou ARN que não é de política falham na validação. |
| `assign_public_ip` | `bool` | `false` | IP público nas tarefas (necessário em subnet pública sem NAT). |
| `container_name` | `string` | `"app"` | Nome do contêiner. |
| `container_port` | `number` | `null` | Porta TCP; nulo não expõe porta. |
| `cpu` / `memory` | `number` | `256` / `512` | Combinação válida do Fargate. |
| `cpu_architecture` | `string` | `"ARM64"` | `ARM64` ou `X86_64`. |
| `command` / `entry_point` | `list(string)` | `null` | Substituem CMD/ENTRYPOINT da imagem. |
| `environment` | `map(string)` | `{}` | Variáveis de ambiente. Nunca segredos. |
| `secrets` | `map(string)` | `{}` | Variável => nome do parâmetro SSM, ARN do parâmetro ou ARN **completo** do Secrets Manager (com o sufixo `-XXXXXX`; chave JSON opcional). |
| `secrets_kms_key_arns` | `list(string)` | `[]` | CMKs dos segredos (`kms:Decrypt`). |
| `ecr_repository_arns` | `list(string)` | `[]` | Repositórios ECR de onde a imagem vem. |
| `task_role_name` / `execution_role_name` | `string` | `null` | Nomes das roles; nulo usa `<name>-task` / `<name>-execution`. |
| `task_role_policies` | `map(string)` | `{}` | Políticas inline da role da tarefa (`ecs-exec` é reservado). |
| `log_group_name` | `string` | `null` | Nome do log group; nulo usa `/ecs/<name>`. |
| `log_retention_in_days` | `number` | `30` | Retenção (valores do CloudWatch Logs). |
| `log_group_kms_key_arn` | `string` | `null` | CMK do log group. |
| `desired_count` | `number` | `1` | Tarefas na criação. |
| `capacity_provider_strategy` | `list(object)` | `[{ capacity_provider = "FARGATE" }]` | `FARGATE` e/ou `FARGATE_SPOT`, com `weight` (padrão 1) e `base` (padrão 0). |
| `deployment_minimum_healthy_percent` | `number` | `100` | Mínimo saudável no deploy. |
| `deployment_maximum_percent` | `number` | `200` | Máximo no deploy. |
| `target_group_arn` | `string` | `null` | Target group (tipo `ip`); exige `container_port`. |
| `health_check_grace_period_seconds` | `number` | `60` | Só com target group. |
| `allowed_security_groups` | `map(string)` | `{}` | Nome lógico => ID de SG com entrada na `container_port`. |
| `egress_rules` | `map(object)` | HTTPS para `0.0.0.0/0` | `{ description, ip_protocol, from_port, to_port, cidr_ipv4 \| referenced_security_group_id \| prefix_list_id }`. |
| `additional_security_group_ids` | `list(string)` | `[]` | SGs extras nas tarefas. |
| `enable_execute_command` | `bool` | `false` | ECS Exec. |
| `readonly_root_filesystem` | `bool` | `false` | Raiz só leitura. |
| `health_check` | `object` | `null` | `{ command, interval = 30, timeout = 5, retries = 3, start_period = 0 }`. |
| `stop_timeout` | `number` | `30` | SIGTERM → SIGKILL (2 a 120 s). |
| `wait_for_steady_state` | `bool` | `false` | Apply espera o serviço estabilizar. |
| `autoscaling_max_capacity` | `number` | `null` | Liga o autoscaling por CPU. |
| `autoscaling_min_capacity` | `number` | `null` | Nulo usa `desired_count`. |
| `autoscaling_cpu_target` | `number` | `70` | % de CPU alvo (10 a 90). |
| `autoscaling_scale_in_cooldown` / `autoscaling_scale_out_cooldown` | `number` | `300` / `60` | Cooldowns em segundos. |
| `alarm_period` / `alarm_evaluation_periods` | `number` | `300` / `3` | Períodos dos alarmes. |
| `cpu_alarm_threshold` / `memory_alarm_threshold` | `number` | `85` / `85` | % que dispara cada alarme. |
| `alarm_actions` / `ok_actions` | `list(string)` | `[]` | ARNs acionados em `ALARM` / `OK`. |
| `tags` | `map(string)` | `{}` | Tags de todos os recursos que aceitam tags. |

## Saídas

| Nome | Descrição |
| --- | --- |
| `service_name`, `service_arn` | Serviço ECS. |
| `task_definition_arn`, `task_definition_family`, `task_definition_revision` | Task definition. |
| `task_role_name`, `task_role_arn` | Role da aplicação. |
| `execution_role_name`, `execution_role_arn` | Role do ECS. |
| `security_group_id` | Security group das tarefas (use em `allowed_security_groups` do RDS). |
| `log_group_name`, `log_group_arn` | Log group. |
| `autoscaling_target_resource_id` | Alvo do autoscaling (nulo sem autoscaling). |
| `alarm_names`, `alarm_arns` | Alarmes, por chave (`cpu`, `memory`). |

## Avisos

- **Segredos só por referência.** `secrets` recebe nomes ou ARNs; o ECS lê o valor ao iniciar a tarefa e o injeta como variável de ambiente. Nenhum valor passa pelo Terraform. Um nome de parâmetro SSM vira ARN na região e conta atuais. O parâmetro precisa existir antes da tarefa subir (SecureString criado pelo administrador). Mudar o valor do segredo só vale para tarefas novas: force um deploy.
- **ARN completo do Secrets Manager.** O ARN de um segredo termina com um sufixo aleatório de 6 caracteres (`...:secret:<nome>-AbCdEf`). O módulo exige esse ARN completo (ex.: `master_user_secret_arn` do `rds-postgres`, ou o `arn` do recurso ou data source do segredo), para que a role de execução receba `secretsmanager:GetSecretValue` só no ARN exato. ARN parcial (sem o sufixo) exigiria curinga `-??????` na política e é recusado na validação. Quando o ARN só é conhecido no apply, a validação fica para o apply.
- **Sem NAT.** Em subnet pública, use `assign_public_ip = true`; sem IP público e sem NAT, a tarefa não puxa a imagem nem lê segredos. O security group continua sem entrada da internet.
- **Saída `0.0.0.0/0` na porta 443.** É o padrão porque, sem NAT nem endpoints de interface, ECR, SSM, Secrets Manager, CloudWatch Logs e APIs externas só são alcançados pelos endpoints públicos. O trivy aponta AWS-0104; a exceção fica no próprio recurso e vale só para regras com `from_port = 443`. Regras mais amplas continuam reprovando.
- **`desired_count` só na criação.** O módulo ignora mudanças nele para não brigar com o autoscaling. Para mudar a contagem sem autoscaling, use `autoscaling_min_capacity = autoscaling_max_capacity`.
- **Fargate Spot** pode interromper a tarefa com 2 minutos de aviso (SIGTERM). Use só em cargas que toleram interrupção (worker idempotente) e trate o SIGTERM dentro de `stop_timeout`.
- **ARM64.** A imagem precisa ser `linux/arm64` (ou multi-arquitetura).
- **Permissões de quem aplica.** Além de ECS, IAM e logs, o deploy precisa de `iam:PassRole` das duas roles para `ecs-tasks.amazonaws.com`, de Application Auto Scaling quando houver autoscaling, e as service-linked roles do ECS e do Application Auto Scaling precisam existir (ou quem aplica precisa poder criá-las).
- **Nomes.** `name`, as roles e o log group precisam caber no prefixo que a role de deploy alcança (ex.: `<org>-<env>-<serviço>-*` e `/<org>/<env>/<serviço>/*`).
