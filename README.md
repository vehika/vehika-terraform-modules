# vehika-terraform-modules

Módulos-template de Terraform da VEHIKA, consumidos pelo `infra/` de cada serviço:

```hcl
module "exemplo" {
  source = "git::https://github.com/vehika/vehika-terraform-modules.git//<módulo>?ref=vX.Y.Z"
}
```

Repositório público: os módulos são genéricos e não contêm IDs de conta, ARNs reais, e-mails nem nomes reais de buckets. Tudo vem por variável.
