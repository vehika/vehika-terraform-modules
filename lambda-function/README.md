# lambda-function

Função Lambda observável com o mínimo de permissões: log group próprio, role de execução com permissions boundary obrigatório, X-Ray ativo e alarme de erros.

## O que cria

| Recurso | Nome | Detalhe |
| --- | --- | --- |
| `aws_cloudwatch_log_group` | `/aws/lambda/<name>` | Criado antes da função; retenção configurável (padrão 30 dias); CMK opcional. |
| `aws_iam_role` | `role_name` (padrão `<name>`) | Caminho `role_path` e `permissions_boundary_arn`, ambos obrigatórios. Confiança só em `lambda.amazonaws.com`. |
| `aws_iam_role_policy` `base` | `base` | `logs:CreateLogStream` e `logs:PutLogEvents` só em `<ARN do log group>:*`; `xray:PutTraceSegments` e `xray:PutTelemetryRecords` em `*` (essas ações não aceitam escopo por recurso). |
| `aws_iam_role_policy` `additional` | chave do mapa | Uma por item de `additional_policies` (ex.: SQS, DynamoDB). |
| `aws_lambda_function` | `<name>` | Upload direto do zip (`filename` + `source_code_hash`), `nodejs24.x`, `arm64`, tracing `Active`, logs em JSON no log group do módulo. |
| `aws_cloudwatch_metric_alarm` | `<name>-errors` | `AWS/Lambda` `Errors`, `Sum`, `FunctionName`, `>= 1` em 1 período de 300 s, `treat_missing_data = notBreaching`. |

Nenhuma política gerenciada da AWS é anexada. O módulo não declara `provider`: a região e as `default_tags` vêm do consumidor. Exige o provider `hashicorp/aws` `>= 6.19, < 7.0` (versões anteriores recusam `nodejs24.x`).

## Uso

```hcl
module "noop" {
  source = "git::https://github.com/vehika/vehika-terraform-modules.git//lambda-function?ref=v0.1.0"

  name                     = "${local.name_prefix}-noop"
  description              = "Handler noop observável."
  filename                 = "${path.module}/../dist/noop.zip"
  source_code_hash         = filebase64sha256("${path.module}/../dist/noop.zip")
  handler                  = "index.handler"
  role_path                = data.aws_ssm_parameter.workload_path.insecure_value
  permissions_boundary_arn = data.aws_ssm_parameter.permissions_boundary_arn.insecure_value

  environment_variables = {
    POWERTOOLS_SERVICE_NAME = "noop"
  }

  additional_policies = {
    queue-access = data.aws_iam_policy_document.queue_access.json
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { service = "<serviço>" }
}
```

Parâmetros `String` da base: use `insecure_value`; `value` é sensível e esconde nomes no plan.

Para permissões além de logs e X-Ray, use `additional_policies`: cada chave vira o nome de uma política inline e o valor é o documento JSON. O documento pode depender de recursos criados na mesma stack (ex.: o ARN de uma fila, conhecido só no apply); as **chaves** precisam ser conhecidas no plan, então use nomes fixos. `base` é reservado para a política do módulo.

Exemplo completo em [`examples/basic`](../examples/basic).

## Variáveis

| Nome | Tipo | Padrão | Descrição |
| --- | --- | --- | --- |
| `name` | `string` | obrigatória | Nome da função (1 a 64 caracteres: letras, números, `-`, `_`). Define o log group, o alarme e, por padrão, a role. |
| `description` | `string` | `""` | Descrição da função. |
| `filename` | `string` | obrigatória | Caminho local do `.zip` (upload direto, até 50 MB compactado). |
| `source_code_hash` | `string` | obrigatória | `filebase64sha256` do zip. |
| `handler` | `string` | obrigatória | Ponto de entrada (ex.: `index.handler`). |
| `runtime` | `string` | `"nodejs24.x"` | Runtime. |
| `architectures` | `list(string)` | `["arm64"]` | Exatamente uma: `arm64` ou `x86_64`. |
| `memory_size` | `number` | `256` | Memória em MB (128 a 10240). |
| `timeout` | `number` | `10` | Timeout em segundos (1 a 900). |
| `reserved_concurrent_executions` | `number` | `-1` | Concorrência reservada; `-1` não reserva. Ver avisos. |
| `environment_variables` | `map(string)` | `{}` | Variáveis de ambiente; vazio não cria o bloco `environment`. Nunca segredos. |
| `tracing_mode` | `string` | `"Active"` | `Active` ou `PassThrough`. |
| `log_format` | `string` | `"JSON"` | `JSON` ou `Text`. |
| `log_retention_in_days` | `number` | `30` | Valores aceitos pelo CloudWatch Logs (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653). |
| `log_group_kms_key_arn` | `string` | `null` | ARN de CMK (`arn:<partição>:kms:...`) para o log group; nulo usa a criptografia gerenciada pelo CloudWatch Logs. |
| `role_name` | `string` | `null` | Nome da role; nulo usa `name`. |
| `role_path` | `string` | obrigatória | Caminho IAM da role, começando e terminando com `/`. |
| `permissions_boundary_arn` | `string` | obrigatória | ARN da política de permissions boundary da role. |
| `additional_policies` | `map(string)` | `{}` | Políticas inline adicionais: nome (1 a 128 caracteres de `A-Za-z0-9_+=,.@-`, diferente de `base`) => documento JSON. |
| `error_alarm_period` | `number` | `300` | Período do alarme em segundos (múltiplo de 60). |
| `error_alarm_evaluation_periods` | `number` | `1` | Períodos avaliados. |
| `error_alarm_threshold` | `number` | `1` | Soma de erros que dispara o alarme (`>=`). |
| `alarm_actions` | `list(string)` | `[]` | ARNs acionados em `ALARM`; aplicadas a todos os alarmes do módulo. |
| `ok_actions` | `list(string)` | `[]` | ARNs acionados na volta para `OK`; aplicadas a todos os alarmes do módulo. |
| `tags` | `map(string)` | `{}` | Tags de todos os recursos que aceitam tags. |

## Saídas

| Nome | Descrição |
| --- | --- |
| `function_name` | Nome da função. |
| `function_arn` | ARN da função. |
| `invoke_arn` | ARN de invocação (integrações do API Gateway). |
| `role_name` | Nome da role de execução. |
| `role_arn` | ARN da role de execução. |
| `log_group_name` | Nome do log group. |
| `log_group_arn` | ARN do log group (sem o sufixo `:*`). |
| `error_alarm_name` | Nome do alarme de erros. |
| `error_alarm_arn` | ARN do alarme de erros. |

## Observabilidade

- **Logs:** formato JSON por padrão, no log group do módulo. A role só escreve nos streams desse log group; não há `logs:CreateLogGroup`, porque o grupo é criado pelo Terraform antes da função.
- **Traces:** X-Ray `Active` por padrão. A role tem só `PutTraceSegments` e `PutTelemetryRecords`; ler traces não faz parte da função.
- **Métricas:** métricas customizadas do Powertools (`Metrics`) usam EMF e saem pelos logs; o CloudWatch as extrai do log group. Por isso a role **não** tem `cloudwatch:PutMetricData`.
- **Alarme:** `<name>-errors` sobre a métrica `Errors` da função. Sem `alarm_actions`, ele só muda de estado no console.

## Avisos

- **Código por upload direto do zip.** O módulo usa `filename` + `source_code_hash` e não aceita zip no S3: o Lambda busca o objeto com as permissões de quem chama `CreateFunction`/`UpdateFunctionCode`, e roles de CI sem leitura de objetos S3 falham. O limite do upload direto é 50 MB compactado.
- **Sem segredos em variáveis de ambiente.** Elas ficam no estado, no plan e visíveis para quem lê a configuração da função (`lambda:GetFunction`). Guarde segredos no SSM Parameter Store (SecureString) ou no Secrets Manager e leia em tempo de execução; passe só o nome do parâmetro.
- **Concorrência reservada.** A AWS mantém pelo menos 100 de concorrência não reservada na conta; com cota menor (contas novas podem ter 10), qualquer reserva falha. Por isso o padrão é `-1` (sem reserva). Peça aumento da cota no Service Quotas antes de reservar. `0` desliga a função.
- **Permissions boundary obrigatório.** `role_path` e `permissions_boundary_arn` não têm padrão: quando a role de deploy só pode criar roles com o boundary do ambiente, o IAM recusa a criação sem ele.
- **Nomes.** `name` e `role_name` precisam caber no prefixo que a role de deploy alcança (ex.: `<org>-<env>-<serviço>-*`); o log group e o alarme seguem `name`.
- **CMK opcional.** Sem `log_group_kms_key_arn`, o log group usa a criptografia gerenciada pelo CloudWatch Logs. Uma CMK exige permissões de KMS para quem aplica e uma key policy que permita o serviço `logs` da região.
