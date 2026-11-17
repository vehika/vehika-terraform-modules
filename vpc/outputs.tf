output "vpc_id" {
  description = "ID da VPC."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "ARN da VPC."
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "Bloco CIDR IPv4 da VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Zonas de disponibilidade usadas, na ordem das subnets."
  value       = var.availability_zones
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas, na ordem de availability_zones."
  value       = aws_subnet.public[*].id
}

output "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas, na ordem de availability_zones."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas, na ordem de availability_zones."
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas, na ordem de availability_zones."
  value       = aws_subnet.private[*].cidr_block
}

output "public_route_table_id" {
  description = "ID da tabela de rotas das subnets públicas."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs das tabelas de rotas das subnets privadas, uma por zona."
  value       = aws_route_table.private[*].id
}

output "internet_gateway_id" {
  description = "ID do internet gateway."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "IDs dos NAT gateways (vazio com nat_gateway_mode = none)."
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "IPs públicos dos NAT gateways (vazio com nat_gateway_mode = none)."
  value       = aws_eip.nat[*].public_ip
}

output "default_security_group_id" {
  description = "ID do security group padrão da VPC, mantido sem regras."
  value       = aws_default_security_group.this.id
}

output "s3_gateway_endpoint_id" {
  description = "ID do endpoint gateway do S3 (nulo quando desligado)."
  value       = one(aws_vpc_endpoint.s3[*].id)
}

output "s3_gateway_endpoint_prefix_list_id" {
  description = "ID da prefix list do S3 na região, útil em regras de saída de security groups (nulo quando o endpoint está desligado)."
  value       = one(aws_vpc_endpoint.s3[*].prefix_list_id)
}

output "flow_log_id" {
  description = "ID do flow log da VPC (nulo quando desligado)."
  value       = one(aws_flow_log.this[*].id)
}

output "flow_logs_log_group_name" {
  description = "Nome do log group dos flow logs (nulo quando desligado ou com destino s3)."
  value       = one(aws_cloudwatch_log_group.flow_logs[*].name)
}

output "flow_logs_role_arn" {
  description = "ARN da role dos flow logs (nulo quando desligado ou com destino s3)."
  value       = one(aws_iam_role.flow_logs[*].arn)
}
