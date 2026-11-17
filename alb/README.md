# alb

Application Load Balancer público com HTTPS obrigatório (certificado do ACM recebido por variável), redirecionamento de 80 para 443, política de TLS moderna, WAFv2 associado (rate limit por IP e regras gerenciadas Common, KnownBadInputs e IpReputation), target groups do tipo `ip` para Fargate, access logs opcionais e alarmes de 5xx, latência e alvos saudáveis.

## O que cria

| Recurso | Nome | Detalhe |
| --- | --- | --- |
| `aws_security_group` | `<name>` | Entrada TCP 80 e 443 de `ingress_cidr_blocks` (padrão `0.0.0.0/0`). Saída só para os `target_security_groups`, na porta de cada um. |
| `aws_lb` | `<name>` | `application`, voltado à internet, IPv4, `drop_invalid_header_fields`, desync `defensive`, HTTP/2, deletion protection; access logs só com `access_logs_bucket`. |
| `aws_lb_target_group` | `<name>-<chave>` (ou `name`) | Um por item de `target_groups`: tipo `ip`, HTTP, deregistration delay 30 s, health check em `traffic-port` (padrão `/`, `200-399`, 15 s). |
| `aws_lb_listener` `http` | — | Porta 80: só redireciona para HTTPS 443 (301). |
| `aws_lb_listener` `https` | — | Porta 443, `ELBSecurityPolicy-TLS13-1-2-2021-06`, `certificate_arn`. Ação padrão: `default_target_group` ou 404 fixo. HSTS opcional. |
| `aws_lb_listener_certificate` | — | Um por item de `additional_certificate_arns` (SNI). |
| `aws_lb_listener_rule` | — | Um por item de `listener_rules` (host e/ou caminho → target group). |
| `aws_wafv2_web_acl` + `aws_wafv2_web_acl_association` | `<name>` | Só com `waf_enabled` (padrão `true`). Regional, ação padrão `allow`, regras abaixo. |
| `aws_wafv2_web_acl_logging_configuration` | — | Só com `waf_log_destination_arn`; omite os cabeçalhos `authorization` e `cookie`. |
| `aws_cloudwatch_metric_alarm` | `<name>-elb-5xx`, `<name>-target-5xx`, `<name>-latency` | `AWS/ApplicationELB` por `LoadBalancer`, 2 períodos de 300 s, `notBreaching`. |
| `aws_cloudwatch_metric_alarm` `healthy_hosts` | `<name>-<chave>-healthy-hosts` | Um por target group: `HealthyHostCount` mínimo `< 1` em 2 períodos de 60 s, `breaching` sem dados. |

O módulo **não cria nem valida certificados** e não cria registros DNS: o certificado do ACM é validado por quem controla o domínio (ex.: CNAME manual no provedor de DNS) e o domínio aponta para `dns_name`. Sem `provider` declarado; exige Terraform `>= 1.11` e `hashicorp/aws` `>= 6.19, < 7.0`.

### Regras do WAF

| Prioridade | Regra | Ação |
| --- | --- | --- |
| 0 | `rate-limit-per-ip` | Bloqueia o IP acima de `waf_rate_limit` (padrão 2000) requisições em `waf_rate_limit_window` (padrão 300 s). |
| 10 | `AWSManagedRulesAmazonIpReputationList` | Bloqueia IPs com má reputação. |
| 20 | `AWSManagedRulesCommonRuleSet` | Bloqueia ataques comuns (OWASP). |
| 30 | `AWSManagedRulesKnownBadInputsRuleSet` | Bloqueia entradas maliciosas conhecidas (ex.: Log4j). |

Uso aproximado: 927 WCU, abaixo das 1500 incluídas no preço base da web ACL. `waf_rule_count_overrides` passa regras específicas de um grupo para só contar.

## Uso

```hcl
module "alb" {
  source = "git::https://github.com/vehika/vehika-terraform-modules.git//alb?ref=v0.2.0"

  name            = "${local.name_prefix}-alb"
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.public_subnet_ids
  certificate_arn = data.aws_ssm_parameter.api_certificate_arn.insecure_value

  target_groups = {
    api = { port = 3000, health_check = { path = "/health" } }
  }
  default_target_group = "api"

  target_security_groups = {
    api = { security_group_id = module.api.security_group_id, port = 3000 }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
```

O `ecs-service` da API recebe `target_group_arn = module.alb.target_group_arns["api"]` e `allowed_security_groups = { alb = module.alb.security_group_id }`. A referência cruzada entre os dois módulos não forma ciclo: as regras de security group são recursos separados. A saída `target_group_arns` só fica disponível depois do listener e das regras, porque o ECS recusa um target group sem load balancer.

Exemplo completo em [`examples/alb`](../examples/alb).

## Variáveis

| Nome | Tipo | Padrão | Descrição |
| --- | --- | --- | --- |
| `name` | `string` | obrigatória | Nome do ALB (1 a 32 caracteres, letras, números e `-`; não começa com `internal-`). |
| `vpc_id` | `string` | obrigatória | VPC do ALB e dos target groups. |
| `subnet_ids` | `list(string)` | obrigatória | Subnets em pelo menos duas zonas. |
| `certificate_arn` | `string` | obrigatória | Certificado do ACM na mesma região. |
| `internal` | `bool` | `false` | ALB interno. |
| `additional_certificate_arns` | `list(string)` | `[]` | Certificados extras (SNI). |
| `ssl_policy` | `string` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | Só políticas `TLS13-*`, `TLS-1-2-*` ou `FS-1-2-*`. |
| `ingress_cidr_blocks` | `list(string)` | `["0.0.0.0/0"]` | Origem permitida em 80 e 443. |
| `target_security_groups` | `map(object)` | `{}` | `{ security_group_id, port }` por alvo: única saída do ALB. |
| `target_groups` | `map(object)` | `{}` | `{ name, port, protocol = "HTTP", protocol_version = "HTTP1", deregistration_delay = 30, slow_start = 0, health_check = { path = "/", matcher = "200-399", interval = 15, timeout = 5, healthy_threshold = 2, unhealthy_threshold = 3 } }`. |
| `default_target_group` | `string` | `null` | Chave do target group padrão; nulo responde 404. |
| `listener_rules` | `map(object)` | `{}` | `{ priority, target_group, host_headers = [], path_patterns = [] }`. |
| `idle_timeout` | `number` | `60` | Segundos (1 a 4000). |
| `desync_mitigation_mode` | `string` | `"defensive"` | `monitor`, `defensive` ou `strictest`. |
| `deletion_protection` | `bool` | `true` | Impede apagar o ALB. |
| `hsts_header_value` | `string` | `null` | `Strict-Transport-Security` acrescentado pelo ALB. |
| `access_logs_bucket` | `string` | `null` | Bucket dos access logs; nulo desliga. |
| `access_logs_prefix` | `string` | `null` | Prefixo; nulo usa `name`. |
| `waf_enabled` | `bool` | `true` | Cria e associa a web ACL. |
| `waf_rate_limit` | `number` | `2000` | Requisições por IP na janela (mínimo 10). |
| `waf_rate_limit_window` | `number` | `300` | `60`, `120`, `300` ou `600` segundos. |
| `waf_forwarded_ip_header` | `string` | `null` | Cabeçalho do IP real quando há proxy na frente. |
| `waf_rule_count_overrides` | `map(list(string))` | `{}` | `common`, `known_bad_inputs` ou `ip_reputation` => regras que só contam. |
| `waf_log_destination_arn` | `string` | `null` | Destino `aws-waf-logs-*` (logs, S3 ou Firehose). |
| `alarm_period` / `alarm_evaluation_periods` | `number` | `300` / `2` | Períodos dos alarmes. |
| `elb_5xx_alarm_threshold` / `target_5xx_alarm_threshold` | `number` | `10` / `10` | 5xx no período (`>=`). |
| `latency_alarm_threshold` | `number` | `2` | p95 em segundos (`>`). |
| `alarm_actions` / `ok_actions` | `list(string)` | `[]` | ARNs acionados em `ALARM` / `OK`. |
| `tags` | `map(string)` | `{}` | Tags de todos os recursos que aceitam tags. |

## Saídas

| Nome | Descrição |
| --- | --- |
| `arn`, `arn_suffix` | ALB e dimensão `LoadBalancer`. |
| `dns_name`, `zone_id` | Alvo do CNAME (ou alias) do domínio. |
| `security_group_id` | Security group do ALB (use em `allowed_security_groups` do `ecs-service`). |
| `http_listener_arn`, `https_listener_arn` | Listeners. |
| `target_group_arns` | ARNs por chave, disponíveis depois do listener e das regras. |
| `target_group_arn_suffixes`, `target_group_names` | Dimensão `TargetGroup` e nomes, por chave. |
| `web_acl_arn`, `web_acl_name` | Web ACL (nulos sem WAF). |
| `alarm_names`, `alarm_arns` | Alarmes, por chave. |

## Avisos

- **Certificado antes do apply.** O listener HTTPS exige um certificado do ACM **emitido**. Com DNS fora da AWS, peça o certificado, crie o CNAME de validação no provedor de DNS e espere o status `ISSUED` antes de aplicar o módulo.
- **Proxy na frente do ALB.** Se o domínio passar por um proxy (ex.: CDN com proxy ligado), o ALB vê o IP do proxy: o rate limit agruparia todos os clientes e a lista de reputação avaliaria o proxy. Use DNS sem proxy ou configure `waf_forwarded_ip_header` (e restrinja `ingress_cidr_blocks` às faixas do proxy).
- **Corpo acima de 8 KB.** A regra `SizeRestrictions_BODY` do grupo Common bloqueia corpos maiores que 8 KB (ex.: upload direto pela API). Se a API recebe uploads, use `waf_rule_count_overrides = { common = ["SizeRestrictions_BODY"] }` ou envie arquivos por URL pré-assinada do S3.
- **ALB público.** O trivy aponta AWS-0053 (load balancer exposto); a exceção fica no próprio `aws_lb`, porque o ALB voltado à internet é a entrada da API por decisão de arquitetura, com WAF associado.
- **Access logs.** O bucket precisa de bucket policy para a entrega do ELB na região e de SSE-S3 (o ELB não grava com SSE-KMS).
- **Destruir exige dois passos.** Com `deletion_protection = true`, desligue a proteção num apply e só então apague.
- **Trocar um target group** (porta, protocolo) recria o recurso com o mesmo nome; a AWS recusa enquanto ele estiver em uso. Mude a chave (novo nome) e migre o serviço.
- **Custo.** O ALB cobra hora e LCU; cada IPv4 público do ALB (um por zona) é cobrado; o WAF cobra a web ACL, cada regra e cada milhão de requisições.
