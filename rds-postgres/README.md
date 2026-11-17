# rds-postgres

Instância RDS PostgreSQL barata e protegida por padrão: PostgreSQL 17 em `db.t4g.micro`, gp3 com autoscaling de armazenamento, PITR configurável, TLS obrigatório, deletion protection, senha master gerenciada pelo RDS no Secrets Manager, cópia opcional dos backups em outra região e alarmes de CPU, memória, armazenamento e conexões.

## O que cria

| Recurso | Nome | Detalhe |
| --- | --- | --- |
| `aws_db_subnet_group` | `<identifier>` | Subnets informadas (normalmente as privadas), em pelo menos duas zonas. |
| `aws_security_group` | `<identifier>-<sufixo>` | `name_prefix` com `create_before_destroy`. **Sem regra de saída.** Entrada só na porta do banco e só dos security groups de `allowed_security_groups` (uma `aws_vpc_security_group_ingress_rule` por item). |
| `aws_db_parameter_group` | `<identifier>-postgres<major>` | `rds.force_ssl = 1` fixo, mais os `parameters` extras. `create_before_destroy` para trocas de família. |
| `aws_db_instance` | `<identifier>` | PostgreSQL `17`, `db.t4g.micro`, gp3 20 GiB com autoscaling até 100 GiB, criptografia sempre ligada (CMK opcional), `manage_master_user_password`, single-AZ, sem acesso público, PITR de 14 dias, deletion protection, snapshot final obrigatório, backups automáticos preservados ao apagar, `copy_tags_to_snapshot`, suporte estendido pago desligado. |
| `aws_db_instance_automated_backups_replication` | — | Só com `backup_replication_enabled`. Criado na região `backup_replication_region` com a chave KMS de lá. |
| `aws_cloudwatch_log_group` `exports` | `/aws/rds/instance/<identifier>/<tipo>` | Um por item de `enabled_cloudwatch_logs_exports`, com retenção e CMK opcional. Vazio por padrão. |
| `aws_cloudwatch_metric_alarm` | `<identifier>-cpu`, `-freeable-memory`, `-free-storage`, `-connections` | `AWS/RDS` por `DBInstanceIdentifier`; 3 períodos de 300 s. |

Sem `provider` declarado: a região e as `default_tags` vêm do consumidor. Exige Terraform `>= 1.11` e `hashicorp/aws` `>= 6.19, < 7.0`.

### Alarmes

| Chave | Métrica | Estatística | Dispara quando | Padrão |
| --- | --- | --- | --- | --- |
| `cpu` | `CPUUtilization` | `Average` | `>` limite | `80` % |
| `freeable-memory` | `FreeableMemory` | `Average` | `<` limite | `104857600` bytes (100 MiB) |
| `free-storage` | `FreeStorageSpace` | `Minimum` | `<` limite | `2147483648` bytes (2 GiB) |
| `connections` | `DatabaseConnections` | `Maximum` | `>` limite | `70` |

`treat_missing_data = missing`. Sem `alarm_actions`, os alarmes só mudam de estado no console.

### Cópia dos backups em outra região

Com `backup_replication_enabled = true`, o módulo cria `aws_db_instance_automated_backups_replication` na região `backup_replication_region` usando o argumento `region` por recurso do provider 6. O consumidor **não** precisa passar um provider com alias. `backup_replication_kms_key_arn` é obrigatório (a instância é sempre criptografada) e precisa ser uma chave **da região de destino**. A retenção da réplica é `backup_replication_retention_period` ou, se nulo, `backup_retention_period`. A réplica permite restaurar com PITR na região de destino.

## Uso

```hcl
module "database" {
  source = "git::https://github.com/vehika/vehika-terraform-modules.git//rds-postgres?ref=v0.1.1"

  identifier  = "${local.name_prefix}-db"
  vpc_id      = module.network.vpc_id
  subnet_ids  = module.network.private_subnet_ids
  kms_key_arn = data.aws_ssm_parameter.data_kms_key_arn.insecure_value

  allowed_security_groups = {
    api    = module.api.security_group_id
    worker = module.worker.security_group_id
  }

  backup_replication_enabled     = true
  backup_replication_region      = "us-east-2"
  backup_replication_kms_key_arn = data.aws_ssm_parameter.replica_kms_key_arn.insecure_value

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
```

As **chaves** de `allowed_security_groups` precisam ser conhecidas no plan (use nomes fixos); os IDs podem vir de recursos criados na mesma stack.

Exemplo completo em [`examples/rds-postgres`](../examples/rds-postgres).

## Variáveis

| Nome | Tipo | Padrão | Descrição |
| --- | --- | --- | --- |
| `identifier` | `string` | obrigatória | Identificador (1 a 53 caracteres minúsculos, letras, números e `-`). Nomeia SG, subnet group, parameter group e alarmes. |
| `vpc_id` | `string` | obrigatória | VPC do security group. |
| `subnet_ids` | `list(string)` | obrigatória | Subnets do subnet group (mínimo 2). |
| `engine_version` | `string` | `"17"` | `<major>` ou `<major>.<minor>`. A família do parameter group sai do major. |
| `engine_lifecycle_support` | `string` | `"open-source-rds-extended-support-disabled"` | Suporte estendido pago. |
| `instance_class` | `string` | `"db.t4g.micro"` | Classe da instância. |
| `allocated_storage` | `number` | `20` | GiB iniciais de gp3 (mínimo 20). |
| `max_allocated_storage` | `number` | `100` | Teto do autoscaling; `0` desliga. |
| `kms_key_arn` | `string` | `null` | CMK do armazenamento; nulo usa `aws/rds`. Trocar recria a instância. |
| `db_name` | `string` | `null` | Banco inicial. |
| `master_username` | `string` | `"postgres"` | Usuário master. |
| `master_user_secret_kms_key_arn` | `string` | `null` | CMK do segredo da senha master; nulo usa `aws/secretsmanager`. |
| `port` | `number` | `5432` | Porta. |
| `allowed_security_groups` | `map(string)` | `{}` | Nome lógico da regra => ID do security group autorizado. |
| `additional_security_group_ids` | `list(string)` | `[]` | Security groups extras na instância. |
| `publicly_accessible` | `bool` | `false` | Endereço público. |
| `multi_az` | `bool` | `false` | Standby síncrono em outra zona. |
| `backup_retention_period` | `number` | `14` | Retenção do PITR (1 a 35; `0` não é aceito). |
| `backup_window` | `string` | `null` | Janela do backup (`hh24:mi-hh24:mi`, UTC). |
| `maintenance_window` | `string` | `null` | Janela de manutenção (`ddd:hh24:mi-ddd:hh24:mi`, UTC). |
| `deletion_protection` | `bool` | `true` | Impede apagar a instância. |
| `final_snapshot_identifier` | `string` | `null` | Nome do snapshot final; nulo usa `<identifier>-final`. |
| `apply_immediately` | `bool` | `false` | Aplica mudanças fora da janela de manutenção. |
| `auto_minor_version_upgrade` | `bool` | `true` | Minor automático. |
| `ca_cert_identifier` | `string` | `"rds-ca-rsa2048-g1"` | CA do certificado do servidor. |
| `iam_database_authentication_enabled` | `bool` | `false` | Autenticação IAM no banco. |
| `performance_insights_enabled` | `bool` | `false` | Performance Insights. |
| `performance_insights_kms_key_arn` | `string` | `null` | CMK do Performance Insights. |
| `enabled_cloudwatch_logs_exports` | `list(string)` | `[]` | `postgresql`, `upgrade`, `iam-db-auth-error`. |
| `log_retention_in_days` | `number` | `30` | Retenção dos log groups exportados. |
| `log_group_kms_key_arn` | `string` | `null` | CMK dos log groups exportados. |
| `parameters` | `list(object)` | `[]` | `{ name, value, apply_method = "immediate" }`; `rds.force_ssl` é reservado. |
| `backup_replication_enabled` | `bool` | `false` | Liga a cópia dos backups em outra região. |
| `backup_replication_region` | `string` | `null` | Região de destino. Obrigatória com a replicação. |
| `backup_replication_kms_key_arn` | `string` | `null` | Chave KMS da região de destino. Obrigatória com a replicação. |
| `backup_replication_retention_period` | `number` | `null` | Retenção da réplica; nulo usa `backup_retention_period`. |
| `alarm_period` | `number` | `300` | Período dos alarmes (múltiplo de 60). |
| `alarm_evaluation_periods` | `number` | `3` | Períodos avaliados. |
| `cpu_alarm_threshold` | `number` | `80` | % de CPU. |
| `freeable_memory_alarm_threshold` | `number` | `104857600` | Bytes de memória livre. |
| `free_storage_alarm_threshold` | `number` | `2147483648` | Bytes de armazenamento livre. |
| `connections_alarm_threshold` | `number` | `70` | Conexões abertas. |
| `alarm_actions` | `list(string)` | `[]` | ARNs acionados em `ALARM`. |
| `ok_actions` | `list(string)` | `[]` | ARNs acionados na volta para `OK`. |
| `tags` | `map(string)` | `{}` | Tags de todos os recursos que aceitam tags. |

## Saídas

| Nome | Descrição |
| --- | --- |
| `identifier`, `arn`, `resource_id` | Identificação da instância. |
| `address`, `endpoint`, `port` | Conexão (`endpoint` é `host:porta`). |
| `db_name`, `master_username` | Banco inicial e usuário master. |
| `master_user_secret_arn` | ARN do segredo do Secrets Manager com a senha master. |
| `security_group_id` | Security group da instância. |
| `db_subnet_group_name`, `parameter_group_name` | Subnet group e parameter group. |
| `log_group_names` | Log groups exportados, por tipo. |
| `backup_replication_id` | ARN dos backups replicados (nulo sem replicação). |
| `alarm_names`, `alarm_arns` | Alarmes, por chave. |

## Avisos

- **Senha master fora do Terraform.** O RDS gera a senha e a guarda num segredo do Secrets Manager (cerca de US$ 0,40/mês). Nada vai para o estado, o plan ou as saídas, só o ARN (`master_user_secret_arn`).
- **A senha master gira sozinha a cada 7 dias.** Com `manage_master_user_password`, o RDS liga a rotação automática do segredo (padrão de 7 dias) e troca a senha no banco. O ECS só lê segredos (`secrets` do `ecs-service`) **quando a tarefa sobe**: uma tarefa que já está rodando continua com a senha antiga e passa a falhar em conexões novas depois da rotação. Escolha uma das opções:
  1. **Recomendado:** um usuário próprio da aplicação, criado por migração, com privilégios mínimos e a senha (ou a `DATABASE_URL`) num SecureString do SSM administrado fora do Terraform. A senha só muda quando o administrador decide, com redeploy planejado. O usuário master fica só para administração.
  2. Usar o segredo do RDS direto na aplicação: referencie `master_user_secret_arn` (ex.: `"${module.database.master_user_secret_arn}:password::"` em `secrets`) e planeje um redeploy logo depois de cada rotação. Outra saída é a aplicação ler o segredo do Secrets Manager em tempo de execução e reconectar quando a autenticação falhar. Mudar a frequência da rotação é feito no Secrets Manager, fora deste módulo.
- **TLS obrigatório.** `rds.force_ssl = 1` recusa conexões sem TLS. Os clientes precisam de `sslmode=require` (ou `verify-full` com o bundle da CA do RDS).
- **Destruir exige dois passos.** Com `deletion_protection = true`, desligue a proteção num apply e só então apague. O snapshot final é sempre tirado, e os backups automáticos ficam até expirar.
- **Trocar a CMK ou o `identifier` recria a instância.** Revise o plan: destruir `aws_db_instance` é perda de dados se não houver restore.
- **Suporte estendido desligado.** No fim do suporte padrão do major, a AWS atualiza o major na janela de manutenção. Planeje a atualização antes ou ligue `open-source-rds-extended-support` (cobrança por vCPU-hora).
- **Replicação entre regiões** cobra o armazenamento dos backups na região de destino e a transferência entre regiões. Quem aplica precisa de permissão de RDS e de KMS na região de destino, e a key policy da chave de destino precisa permitir o RDS.
- **Classes pequenas.** `db.t4g.micro` tem 1 GiB de memória e créditos de CPU; os limites de memória livre e conexões dos alarmes foram escolhidos para ela. Ajuste ao trocar de classe.
- **Acesso público.** `publicly_accessible = true` só funciona em subnets públicas e ainda depende do security group; evite.
