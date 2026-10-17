# Changelog

Versões do repositório inteiro (tags `vX.Y.Z`). Ver [Versionamento](README.md#versionamento).

## 0.1.0 (2026-10-17)

### Adicionado

- Módulo `lambda-function`: função Lambda com upload direto do zip, `nodejs24.x` e `arm64` por padrão, log group `/aws/lambda/<name>` com retenção configurável, role de execução com caminho e permissions boundary obrigatórios, política inline mínima (logs no próprio log group e envio de traces do X-Ray), políticas inline adicionais opcionais (`additional_policies`, com documentos que podem ser conhecidos só no apply), CMK opcional no log group (`log_group_kms_key_arn`), X-Ray `Active`, logs em JSON e alarme `<name>-errors`.
- Exemplo `examples/basic`.
- Requisitos: Terraform `>= 1.11` e provider `hashicorp/aws` `>= 6.19, < 7.0` (antes da 6.19.0 o provider recusa o runtime `nodejs24.x`).
- CI com guarda contra dados reais, `fmt`, `validate`, `test`, `tflint` e `trivy config`.
