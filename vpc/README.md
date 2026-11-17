# vpc

VPC de baixo custo com subnets públicas e privadas em duas ou mais zonas, endpoint gateway do S3, flow logs opcionais e **sem NAT por padrão**, com NAT opcional para a fase de alta disponibilidade.

## O que cria

| Recurso | Nome (tag `Name`) | Detalhe |
| --- | --- | --- |
| `aws_vpc` | `<name>` | `cidr_block` (padrão `10.0.0.0/16`), DNS support e DNS hostnames ligados. |
| `aws_default_security_group` | `<name>-default` | Assume o security group padrão e remove todas as regras dele. |
| `aws_internet_gateway` | `<name>` | Saída das subnets públicas. |
| `aws_subnet` `public` | `<name>-public-<az>` | Uma por zona, tag `tier = public`, `map_public_ip_on_launch = false`. |
| `aws_subnet` `private` | `<name>-private-<az>` | Uma por zona, tag `tier = private`. |
| `aws_route_table` `public` + `aws_route` | `<name>-public` | Rota `0.0.0.0/0` para o internet gateway. |
| `aws_route_table` `private` | `<name>-private-<az>` | Uma por zona, mesmo sem NAT. Com NAT, ganha a rota `0.0.0.0/0` para ele. |
| `aws_eip` + `aws_nat_gateway` | `<name>-<az>` | Só com `nat_gateway_mode` `single` (1) ou `one_per_az` (1 por zona). |
| `aws_vpc_endpoint` `s3` | `<name>-s3` | Gateway, associado à tabela pública e às privadas. Sem custo. |
| `aws_flow_log` | `<name>` | Só com `flow_logs_enabled`. Destino CloudWatch Logs (log group e role do módulo) ou S3. |
| `aws_cloudwatch_log_group` + `aws_iam_role` | `/vpc/<name>/flow-logs`, `<name>-flow-logs` | Só com flow logs no CloudWatch Logs. Role com caminho e permissions boundary obrigatórios nesse caso. |

Sem `provider` declarado: a região e as `default_tags` vêm do consumidor. Exige Terraform `>= 1.11` e `hashicorp/aws` `>= 6.19, < 7.0`.

### CIDRs calculados

Sem `public_subnet_cidrs`/`private_subnet_cidrs`, cada subnet usa `cidrsubnet(cidr_block, subnet_newbits, índice)`: as públicas no início do espaço e as privadas a partir da metade. Com `/16` e `subnet_newbits = 8`:

| Zona | Pública | Privada |
| --- | --- | --- |
| 1ª | `10.0.0.0/24` | `10.0.128.0/24` |
| 2ª | `10.0.1.0/24` | `10.0.129.0/24` |

Acrescentar uma zona no fim da lista não desloca os CIDRs existentes. Mudar a **ordem** das zonas recria subnets.

## Uso

```hcl
module "network" {
  source = "git::https://github.com/vehika/vehika-terraform-modules.git//vpc?ref=v0.1.1"

  name               = local.name_prefix
  availability_zones = ["us-east-1a", "us-east-1b"]

  # Fase de alta disponibilidade: "single" ou "one_per_az".
  nat_gateway_mode = "none"

  flow_logs_enabled        = true
  flow_logs_log_group_name = "/<org>/<env>/<serviço>/vpc-flow-logs"
  role_path                = data.aws_ssm_parameter.workload_path.insecure_value
  permissions_boundary_arn = data.aws_ssm_parameter.permissions_boundary_arn.insecure_value
}
```

Exemplo completo em [`examples/vpc`](../examples/vpc).

## Variáveis

| Nome | Tipo | Padrão | Descrição |
| --- | --- | --- | --- |
| `name` | `string` | obrigatória | Prefixo dos nomes (1 a 48 caracteres: letras, números e `-`). |
| `cidr_block` | `string` | `"10.0.0.0/16"` | CIDR IPv4 da VPC, de `/16` a `/24`. |
| `availability_zones` | `list(string)` | obrigatória | De 2 a 6 zonas distintas. Uma subnet pública e uma privada por zona. |
| `subnet_newbits` | `number` | `8` | Bits somados à máscara da VPC no cálculo das subnets (2 a 12). |
| `public_subnet_cidrs` | `list(string)` | `null` | CIDRs explícitos das públicas, um por zona. |
| `private_subnet_cidrs` | `list(string)` | `null` | CIDRs explícitos das privadas, um por zona. |
| `nat_gateway_mode` | `string` | `"none"` | `none`, `single` ou `one_per_az`. |
| `s3_gateway_endpoint_enabled` | `bool` | `true` | Cria o endpoint gateway do S3. |
| `s3_gateway_endpoint_policy` | `string` | `null` | Política JSON do endpoint; nulo usa a padrão da AWS. |
| `flow_logs_enabled` | `bool` | `false` | Liga os flow logs. |
| `flow_logs_destination_type` | `string` | `"cloud-watch-logs"` | `cloud-watch-logs` ou `s3`. |
| `flow_logs_traffic_type` | `string` | `"ALL"` | `ALL`, `ACCEPT` ou `REJECT`. |
| `flow_logs_max_aggregation_interval` | `number` | `600` | `60` ou `600` segundos. |
| `flow_logs_s3_bucket_arn` | `string` | `null` | ARN do bucket (com prefixo opcional). Obrigatório no destino `s3`. |
| `flow_logs_log_group_name` | `string` | `null` | Nome do log group; nulo usa `/vpc/<name>/flow-logs`. |
| `flow_logs_retention_in_days` | `number` | `30` | Retenção do log group (valores do CloudWatch Logs). |
| `flow_logs_kms_key_arn` | `string` | `null` | CMK do log group; nulo usa a criptografia gerenciada pelo CloudWatch Logs. |
| `flow_logs_role_name` | `string` | `null` | Nome da role; nulo usa `<name>-flow-logs`. |
| `role_path` | `string` | `null` | Caminho IAM da role. Obrigatório com flow logs no CloudWatch Logs. |
| `permissions_boundary_arn` | `string` | `null` | Boundary da role. Obrigatório com flow logs no CloudWatch Logs. |
| `tags` | `map(string)` | `{}` | Tags de todos os recursos que aceitam tags. |

## Saídas

| Nome | Descrição |
| --- | --- |
| `vpc_id`, `vpc_arn`, `vpc_cidr_block` | Identificação da VPC. |
| `availability_zones` | Zonas usadas, na ordem das subnets. |
| `public_subnet_ids`, `public_subnet_cidrs` | Subnets públicas, na ordem das zonas. |
| `private_subnet_ids`, `private_subnet_cidrs` | Subnets privadas, na ordem das zonas. |
| `public_route_table_id`, `private_route_table_ids` | Tabelas de rotas. |
| `internet_gateway_id` | Internet gateway. |
| `nat_gateway_ids`, `nat_public_ips` | NATs e IPs públicos (vazios sem NAT). |
| `default_security_group_id` | Security group padrão, sem regras. |
| `s3_gateway_endpoint_id`, `s3_gateway_endpoint_prefix_list_id` | Endpoint do S3 e prefix list (nulos quando desligado). |
| `flow_log_id`, `flow_logs_log_group_name`, `flow_logs_role_arn` | Flow logs (nulos quando desligados). |

## Avisos

- **Sem NAT, as subnets privadas não saem para a internet.** Elas servem a recursos que só recebem conexões (ex.: RDS). Tarefas que precisam de internet (imagens do ECR, SSM, APIs externas) ficam nas subnets **públicas**, com IP público atribuído por quem lança (ex.: `assign_public_ip` do ECS) e security group sem entrada da internet. O S3 é alcançado pelo endpoint gateway nos dois tipos de subnet.
- **NAT tem custo fixo.** Cada NAT gateway cobra por hora e por GB processado, mais o IPv4 público do EIP. `single` é um ponto único de falha por zona; `one_per_az` é o desenho de alta disponibilidade.
- **IPv4 público é cobrado.** Cada IP público atribuído a uma tarefa ou NAT é cobrado por hora.
- **Flow logs no CloudWatch Logs** criam uma role: quando a role de deploy só pode criar roles com o boundary do ambiente, `role_path` e `permissions_boundary_arn` são obrigatórios. O nome do log group precisa caber no prefixo que a role de deploy alcança.
- **Flow logs no S3** não criam role; a bucket policy precisa permitir `delivery.logs.amazonaws.com`.
- **Security group padrão:** o módulo remove as regras dele. Não use o grupo padrão; cada recurso deve ter o próprio.
