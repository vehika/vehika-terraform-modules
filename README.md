# vehika-terraform-modules

Módulos-template de Terraform da VEHIKA, consumidos pelo `infra/` de cada serviço.

## Repositório público: nenhum dado real

Este repositório é **público**. Os módulos são genéricos e não contêm IDs de conta, ARNs reais, e-mails, nomes reais de buckets nem nomes físicos de recursos da VEHIKA. Tudo vem por variável, inclusive nos exemplos e testes (sem padrões sensíveis). O CI falha se algum arquivo versionado tiver um número de 12 dígitos isolado, um ARN com ID de conta, um e-mail ou um nome físico de ambiente da VEHIKA (`vehika-<global|staging|production>` ou os caminhos `/vehika/<global|staging|production|ci|bootstrap>/`).

## Como consumir

```hcl
module "exemplo" {
  source = "git::https://github.com/vehika/vehika-terraform-modules.git//<módulo>?ref=vX.Y.Z"
}
```

Fixe sempre uma tag (`?ref=vX.Y.Z`), nunca uma branch. Os módulos não declaram `provider`: região, credenciais e `default_tags` vêm do consumidor.

## Módulos

| Módulo | Descrição | Desde |
| --- | --- | --- |
| [`lambda-function`](lambda-function) | Função Lambda com log group próprio, role com permissions boundary obrigatório, X-Ray e alarme de erros. | `v0.1.0` |

Exemplos em [`examples/`](examples).

## Versionamento

- Uma única versão semântica para o repositório inteiro, em tags `vX.Y.Z` (não há tag por módulo).
- `0.x` enquanto a API dos módulos ainda muda. Em `0.x`, mudança incompatível sobe o **minor** (`0.1.0` → `0.2.0`); recurso compatível ou correção sobe o **patch**.
- A partir de `1.0.0`, mudança incompatível sobe o **major**, recurso compatível o minor e correção o patch.
- É incompatível: remover ou renomear variável ou saída, tornar uma variável obrigatória, mudar um padrão de forma que altere recursos existentes, ou trocar o endereço de um recurso sem bloco `moved`.
- Cada versão tem uma seção no [`CHANGELOG.md`](CHANGELOG.md).

## Como lançar uma versão

1. Abra um PR para a `main` com a mudança e a seção nova do `CHANGELOG.md`.
2. Faça o merge com o CI verde.
3. O administrador cria a tag anotada no commit da `main` e a publica:

   ```sh
   git switch main && git pull --ff-only
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

4. Atualize a data da versão no `CHANGELOG.md` no próximo PR.

Tags publicadas não são movidas nem apagadas: uma correção vira uma versão nova.

## CI

O workflow [`ci`](.github/workflows/ci.yml) roda em PR para a `main` e em push na `main`, com `GITHUB_TOKEN` só leitura:

- guarda contra dados reais em **todos** os arquivos versionados (texto): números de 12 dígitos isolados, ARNs com ID de conta, e-mails, `vehika-<global|staging|production>` e `/vehika/<global|staging|production|ci|bootstrap>/`. Achado reprova; erro do `git grep` também;
- `terraform fmt -check -recursive`;
- `terraform init -backend=false` e `validate` em cada módulo e exemplo;
- `terraform test` em cada módulo (com `mock_provider`, sem credenciais AWS);
- `tflint --recursive` com [`.tflint.hcl`](.tflint.hcl) (ruleset aws 0.49.0);
- `trivy config` (HIGH e CRITICAL reprovam), com as exceções justificadas em [`.trivyignore.yaml`](.trivyignore.yaml).

A versão do Terraform vem de [`.terraform-version`](.terraform-version). As actions são fixadas por SHA e atualizadas pelo Dependabot. O `.terraform.lock.hcl` não é versionado: módulos não fixam lock, quem fixa é o consumidor.

Para rodar localmente, num módulo:

```sh
terraform init -backend=false
terraform validate
terraform test
```

Quando um teste precisa de um ID de conta com formato válido (o provider valida ARNs), use sempre o mesmo ID fictício, gerado com `format("%012d", 0)`, em vez de escrever o número: a guarda recusa números de 12 dígitos literais. Nomes nos testes e exemplos são genéricos (`example-*`).

## Disciplina da `main` (GitHub Free)

Repositório público no GitHub Free: não há proteção técnica de branch configurada. A disciplina é:

- só o administrador tem permissão de escrita;
- toda mudança entra por PR, com o CI verde antes do merge; nada de push direto na `main`;
- PRs de fork exigem aprovação do administrador para rodar o CI;
- tags de versão são criadas só pelo administrador.

## Adicionar um módulo

1. Crie `<módulo>/` com `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `README.md` e `tests/`.
2. Crie `examples/<exemplo>/` chamando `source = "../../<módulo>"`.
3. Inclua os diretórios no `validate`/`test` do [`ci.yml`](.github/workflows/ci.yml) e no [`dependabot.yml`](.github/dependabot.yml).
4. Acrescente o módulo na tabela acima e no `CHANGELOG.md`.
