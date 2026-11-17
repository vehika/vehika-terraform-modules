output "vpc_id" {
  description = "ID da VPC criada."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas."
  value       = module.network.private_subnet_ids
}
