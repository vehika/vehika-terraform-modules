## Resumo

<!-- O que muda e por quê. -->

## Issue

<!-- Link da issue no Linear (ex.: VEH-00). -->

## Checks

- [ ] `terraform fmt -check -recursive`
- [ ] `terraform validate` nos módulos e exemplos alterados
- [ ] `terraform test` nos módulos alterados
- [ ] `tflint --recursive` e `trivy config` sem achados novos
- [ ] Nenhum ID de conta, ARN real, e-mail ou nome real de recurso

## Impacto em consumidores e versão

- [ ] Compatível (patch: correção; minor: recurso novo)
- [ ] Incompatível (em `0.x` sobe o minor; a partir de `1.0`, o major)

<!-- Variáveis, saídas ou recursos que mudam para quem consome, e se exige `moved`/migração. Atualize o CHANGELOG.md. -->
