# Changelog

Versões do repositório inteiro (tags `vX.Y.Z`). Ver [Versionamento](README.md#versionamento).

## 0.1.2 (2026-11-17)

### Adicionado

- `ecs-service`: variável `availability_zone_rebalancing` (`ENABLED` ou `DISABLED`, padrão `ENABLED`) no lugar do `ENABLED` fixo do `aws_ecs_service`. Ela permite um serviço com deploy `0/100` (`deployment_minimum_healthy_percent = 0` e `deployment_maximum_percent = 100`), como um worker com crons que não podem rodar em dobro.
  - Causa: a AWS recusa a criação do serviço com o rebalanceamento ligado e `maximumPercent` de 100%: `InvalidParameterException: The service couldn't be created because Availability Zone Rebalancing does not support maximumPercent <= 100 % as deployment configuration.` A `v0.1.1` fixava `ENABLED`, então não havia como criar um serviço `0/100` com o módulo.
  - Fonte: "Balancing an Amazon ECS service across Availability Zones", seção "Considerations for configuring Availability Zone rebalancing", no Amazon ECS Developer Guide (`service-rebalancing.html`, consultado em 17/11/2026). Entre os critérios que impedem o rebalanceamento estão: "Uses 100% for the maximumPercent value", a estratégia Daemon, o launch type EXTERNAL, Classic Load Balancer e a restrição de posicionamento `attribute:ecs.availability-zone`. Só o critério do `maximumPercent` se aplica ao módulo (Fargate por capacity provider, ALB e sem placement).
  - Validação nova: `ENABLED` exige `deployment_maximum_percent` maior que 100. A mensagem cita o erro da AWS e manda usar `DISABLED` no deploy `0/100`. A combinação recusada falhava antes no apply e agora falha no plan; nenhuma configuração que a AWS aceitava deixa de passar.
  - Compatível: com o padrão `ENABLED`, quem está na `v0.1.1` e passa para a `v0.1.2` recebe `No changes` no `aws_ecs_service`, porque o valor enviado é o mesmo.
- `ecs-service`: testes do padrão `ENABLED`, do worker `0/100` com `DISABLED`, da recusa de `ENABLED` com `deployment_maximum_percent = 100` e da recusa de valor inválido.

### Corrigido

- `ecs-service`: o README e a descrição de `capacity_provider_strategy` deixam de sugerir Fargate Spot com a arquitetura padrão `ARM64`. A documentação do ECS ("Amazon ECS clusters for Fargate", consultada em 17/11/2026) não confirma Fargate Spot com `ARM64`. A recomendação passa a ser `FARGATE` com `ARM64`, ou Spot com `X86_64` depois de validar. O README ganha o exemplo do worker `0/100` com `availability_zone_rebalancing = "DISABLED"`.
- Exemplos `examples/complete` e `examples/ecs-service`: o worker passa de `FARGATE_SPOT` para `FARGATE` (ARM64), e o worker `0/100` do `examples/complete` usa `availability_zone_rebalancing = "DISABLED"`. Os clusters continuam com os dois capacity providers.

- `rds-postgres`: o parâmetro fixo `rds.force_ssl` (valor `1`, ainda sem sobrescrita) passa a usar `apply_method = "pending-reboot"` em vez de `immediate`. Isso acaba com o diff perpétuo no `aws_db_parameter_group` depois do primeiro apply (sai `pending-reboot`, entra `immediate`, com o mesmo `value = "1"`).
  - Causa: a partir do PostgreSQL 15 o padrão do `rds.force_ssl` na AWS já é `1`. Como o valor enviado é igual ao padrão, a AWS não o guarda como parâmetro do usuário e devolve o padrão do sistema com `pending-reboot`. Ela não troca só o `apply_method` sem mudar o `value`, então o `immediate` enviado pelo módulo nunca é gravado. O provider `hashicorp/aws` 6.x documenta esse comportamento em "Problematic Plan Changes" na página do recurso `aws_db_parameter_group` (solução 3: alinhar o `apply_method` com o da AWS).
  - Evidência no ambiente, 17/11/2026: o `describe-db-parameters` no parameter group criado pela `v0.1.1` (PostgreSQL 17) devolve, para o `rds.force_ssl`, `ParameterValue = "1"`, `ApplyMethod = "pending-reboot"`, `ApplyType = "dynamic"` e `Source = "system"`. O `ParameterApplyStatus` da instância é `in-sync`.
  - O parâmetro continua explícito no módulo, para garantir o `1` também em famílias cujo padrão é `0` (PostgreSQL 14 ou anterior). Nelas, o valor é aplicado quando a instância sobe com o parameter group do módulo. Trocar o parameter group de uma instância que já existe exige reboot de qualquer forma.
  - O parâmetro é **dinâmico** no RDS para PostgreSQL (tabela "RDS for PostgreSQL DB instance parameter list", coluna Apply_Type, no guia "Working with parameters on your RDS for PostgreSQL DB instance"; padrão `1` desde o 15 segundo "Requiring an SSL connection to a PostgreSQL DB instance", ambos no RDS User Guide). Como o valor não muda, o `pending-reboot` não exige reboot e o TLS continua obrigatório.
  - Compatível no PostgreSQL 15 ou mais novo, onde o padrão da AWS é `1`: quem está na `v0.1.1` e passa para a `v0.1.2` recebe `No changes` no parameter group, porque o estado já guarda o `pending-reboot` lido da AWS. Nenhum outro recurso do módulo muda.
  - No PostgreSQL 14 ou anterior (padrão `0`), o `rds.force_ssl` é parâmetro do usuário e a AWS o guarda como `immediate`. Lá, a `v0.1.2` mostra um `~` em lugar no parameter group (sai `immediate`, entra `pending-reboot`, mesmo `value = "1"`). Avalie esse `~` antes de aplicar.
- `rds-postgres`: teste que confere o `apply_method` do `rds.force_ssl` e aviso no README sobre `apply_method` em parâmetros com o valor padrão da AWS.

## 0.1.1 (2026-11-17)

### Adicionado

- Módulo `vpc`: VPC com DNS, uma subnet pública e uma privada por zona (2 a 6 zonas, CIDRs calculados ou explícitos, nenhuma subnet atribui IP público por padrão), internet gateway, tabelas privadas por zona, NAT opcional (`nat_gateway_mode` `none` por padrão, `single` ou `one_per_az`), endpoint gateway do S3 em todas as tabelas, security group padrão sem regras e flow logs opcionais no CloudWatch Logs (log group e role com permissions boundary obrigatório) ou no S3.
- Módulo `rds-postgres`: PostgreSQL 17 em `db.t4g.micro`, gp3 com autoscaling de armazenamento, criptografia sempre ligada com CMK opcional, `manage_master_user_password` com CMK opcional do segredo, parameter group próprio com `rds.force_ssl = 1`, PITR configurável (1 a 35 dias, padrão 14), deletion protection, snapshot final obrigatório, backups automáticos preservados, suporte estendido pago desligado, single-AZ e sem acesso público por padrão (Multi-AZ e acesso público por variável), security group sem saída e com entrada só dos SGs autorizados, replicação dos backups automáticos para outra região (`aws_db_instance_automated_backups_replication` pelo argumento `region` do provider 6, sem provider com alias, com chave KMS da região de destino), exportação de logs opcional com log groups próprios e alarmes de CPU, memória livre, armazenamento livre e conexões.
- Módulo `ecs-service`: task definition Fargate `ARM64` de um contêiner, segredos do SSM (nome ou ARN) ou do Secrets Manager só por `valueFrom`, capacity provider strategy com `FARGATE` e/ou `FARGATE_SPOT`, circuit breaker com rollback, autoscaling por CPU opcional, log group com retenção e CMK opcional, roles de tarefa e de execução com caminho e permissions boundary obrigatórios (sem padrão, validados) e políticas com ARNs exatos, security group com entrada só dos SGs informados e saída por regras (padrão só TCP 443), ECS Exec opcional e alarmes de CPU e memória.
- Módulo `alb`: ALB voltado à internet com listener HTTPS (certificado do ACM por variável; o módulo não cria certificado, validação nem DNS), redirecionamento 301 de 80 para 443, `ELBSecurityPolicy-TLS13-1-2-2021-06`, `drop_invalid_header_fields`, desync `defensive`, deletion protection, target groups do tipo `ip`, regras por host e caminho, certificados SNI, HSTS opcional, access logs opcionais, WAFv2 associado com rate limit por IP (cabeçalho de IP encaminhado opcional) e as regras gerenciadas IpReputation, Common e KnownBadInputs (exceções em modo count por variável, logs opcionais com `authorization` e `cookie` omitidos) e alarmes de 5xx do ALB, 5xx dos alvos, latência p95 e alvos saudáveis por target group.
- Security groups do `rds-postgres`, do `ecs-service` e do `alb` com `name_prefix` (`<nome>-`) e `create_before_destroy`.
- `ecs-service`: `secrets` aceita só o ARN **completo** do Secrets Manager (com o sufixo `-XXXXXX`, inclusive `rds!db-...`), para a política da role de execução usar o ARN exato, sem curinga.
- Exemplos `examples/vpc`, `examples/rds-postgres`, `examples/ecs-service` (com cluster e capacity providers), `examples/alb` e `examples/complete` (vpc + alb + API e worker no `ecs-service` + `rds-postgres`, com as referências cruzadas de security group).
- Teste de plan da composição no `ecs-service` (`tests/composition`), com o ARN do target group, os IDs dos security groups e o ARN do segredo do RDS conhecidos só no apply.
- Exceções do `trivy` por comentário no recurso: `AWS-0104` na saída HTTPS do `ecs-service` e `AWS-0053` no ALB público. A entrada `0.0.0.0/0` do ALB só em 80 e 443 é exceção declarada no README do `alb`.
- CI: `validate` nos módulos e exemplos novos e `terraform test` nos módulos novos; Dependabot nos mesmos diretórios.

## 0.1.0 (2026-10-17)

### Adicionado

- Módulo `lambda-function`: função Lambda com upload direto do zip, `nodejs24.x` e `arm64` por padrão, log group `/aws/lambda/<name>` com retenção configurável, role de execução com caminho e permissions boundary obrigatórios, política inline mínima (logs no próprio log group e envio de traces do X-Ray), políticas inline adicionais opcionais (`additional_policies`, com documentos que podem ser conhecidos só no apply), CMK opcional no log group (`log_group_kms_key_arn`), X-Ray `Active`, logs em JSON e alarme `<name>-errors`.
- Exemplo `examples/basic`.
- Requisitos: Terraform `>= 1.11` e provider `hashicorp/aws` `>= 6.19, < 7.0` (antes da 6.19.0 o provider recusa o runtime `nodejs24.x`).
- CI com guarda contra dados reais, `fmt`, `validate`, `test`, `tflint` e `trivy config`.
