data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  az_count = length(var.availability_zones)

  # Públicas no início do espaço e privadas a partir da metade: acrescentar
  # uma zona não desloca os CIDRs existentes.
  private_offset = pow(2, var.subnet_newbits - 1)

  public_subnet_cidrs  = var.public_subnet_cidrs != null ? var.public_subnet_cidrs : [for index in range(local.az_count) : cidrsubnet(var.cidr_block, var.subnet_newbits, index)]
  private_subnet_cidrs = var.private_subnet_cidrs != null ? var.private_subnet_cidrs : [for index in range(local.az_count) : cidrsubnet(var.cidr_block, var.subnet_newbits, local.private_offset + index)]

  nat_gateway_count = {
    none       = 0
    single     = 1
    one_per_az = local.az_count
  }[var.nat_gateway_mode]

  flow_logs_to_cloudwatch = var.flow_logs_enabled && var.flow_logs_destination_type == "cloud-watch-logs"
  flow_logs_to_s3         = var.flow_logs_enabled && var.flow_logs_destination_type == "s3"
  flow_logs_log_group     = coalesce(var.flow_logs_log_group_name, "/vpc/${var.name}/flow-logs")
  flow_logs_role_name     = coalesce(var.flow_logs_role_name, "${var.name}-flow-logs")
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = var.name })
}

# Assume o security group padrão e remove todas as regras dele: nada usa o
# grupo padrão por engano.
resource "aws_default_security_group" "this" {
  vpc_id  = aws_vpc.this.id
  ingress = []
  egress  = []
  tags    = merge(var.tags, { Name = "${var.name}-default" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = var.name })
}

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = local.public_subnet_cidrs[count.index]

  # IP público só quando quem lança pede (ex.: assign_public_ip do ECS).
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.name}-public-${var.availability_zones[count.index]}", tier = "public" })
}

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.availability_zones[count.index]
  cidr_block              = local.private_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.name}-private-${var.availability_zones[count.index]}", tier = "private" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Uma tabela por zona, mesmo sem NAT: ligar o NAT por zona depois não troca
# as associações.
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private-${var.availability_zones[count.index]}" })
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-${var.availability_zones[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(var.tags, { Name = "${var.name}-${var.availability_zones[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat" {
  count = local.nat_gateway_count > 0 ? local.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.nat_gateway_mode == "single" ? 0 : count.index].id
}

resource "aws_vpc_endpoint" "s3" {
  count = var.s3_gateway_endpoint_enabled ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.public.id], aws_route_table.private[*].id)
  policy            = var.s3_gateway_endpoint_policy
  tags              = merge(var.tags, { Name = "${var.name}-s3" })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = local.flow_logs_to_cloudwatch ? 1 : 0

  name              = local.flow_logs_log_group
  retention_in_days = var.flow_logs_retention_in_days
  kms_key_id        = var.flow_logs_kms_key_arn
  tags              = var.tags
}

resource "aws_iam_role" "flow_logs" {
  count = local.flow_logs_to_cloudwatch ? 1 : 0

  name                 = local.flow_logs_role_name
  path                 = var.role_path
  description          = "Entrega dos flow logs da VPC ${var.name} no CloudWatch Logs."
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "FlowLogsAssumeRole"
        Effect    = "Allow"
        Action    = "sts:AssumeRole"
        Principal = { Service = "vpc-flow-logs.amazonaws.com" }
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = local.flow_logs_to_cloudwatch ? 1 : 0

  name = "flow-logs"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteFlowLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
      },
    ]
  })
}

resource "aws_flow_log" "this" {
  count = var.flow_logs_enabled ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs_traffic_type
  max_aggregation_interval = var.flow_logs_max_aggregation_interval
  log_destination_type     = var.flow_logs_destination_type
  log_destination          = local.flow_logs_to_s3 ? var.flow_logs_s3_bucket_arn : aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = local.flow_logs_to_cloudwatch ? aws_iam_role.flow_logs[0].arn : null
  tags                     = merge(var.tags, { Name = var.name })

  depends_on = [aws_iam_role_policy.flow_logs]
}
