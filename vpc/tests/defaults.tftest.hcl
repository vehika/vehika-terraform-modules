mock_provider "aws" {
  override_during = plan

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  # IDs distintos por instância provam que o endpoint usa a tabela pública e
  # as duas privadas.
  override_resource {
    target = aws_route_table.public
    values = {
      id = "rtb-public"
    }
  }

  override_resource {
    target = aws_route_table.private[0]
    values = {
      id = "rtb-private-a"
    }
  }

  override_resource {
    target = aws_route_table.private[1]
    values = {
      id = "rtb-private-b"
    }
  }
}

variables {
  name               = "example-net"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

run "vpc_defaults" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16" && aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "A VPC padrão deve ser 10.0.0.0/16 com DNS habilitado."
  }

  assert {
    condition     = aws_vpc.this.tags["Name"] == "example-net"
    error_message = "A VPC deve ter a tag Name igual a var.name."
  }

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "O security group padrão deve ficar sem regras."
  }
}

run "subnets" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "Deve haver uma subnet pública e uma privada por zona."
  }

  assert {
    condition     = aws_subnet.public[*].cidr_block == ["10.0.0.0/24", "10.0.1.0/24"]
    error_message = "As subnets públicas devem ocupar o início do espaço."
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.0.128.0/24", "10.0.129.0/24"]
    error_message = "As subnets privadas devem começar na metade do espaço."
  }

  assert {
    condition     = aws_subnet.public[*].availability_zone == ["us-east-1a", "us-east-1b"] && aws_subnet.private[*].availability_zone == ["us-east-1a", "us-east-1b"]
    error_message = "As subnets devem seguir a ordem de availability_zones."
  }

  assert {
    condition     = alltrue([for subnet in concat(aws_subnet.public, aws_subnet.private) : subnet.map_public_ip_on_launch == false])
    error_message = "Nenhuma subnet deve atribuir IP público por padrão."
  }

  assert {
    condition     = aws_subnet.public[0].tags["tier"] == "public" && aws_subnet.private[0].tags["tier"] == "private"
    error_message = "As subnets devem ter a tag tier."
  }
}

run "routing_without_nat" {
  command = plan

  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "A tabela pública deve ter rota padrão para o internet gateway."
  }

  assert {
    condition     = length(aws_route_table.private) == 2 && [for association in aws_route_table_association.private : association.route_table_id] == ["rtb-private-a", "rtb-private-b"]
    error_message = "Cada subnet privada deve se associar à tabela privada da própria zona."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_nat) == 0
    error_message = "Por padrão não deve haver NAT, EIP nem rota privada para a internet."
  }
}

run "s3_endpoint" {
  command = plan

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 1
    error_message = "O endpoint gateway do S3 deve existir por padrão."
  }

  assert {
    condition     = aws_vpc_endpoint.s3[0].service_name == "com.amazonaws.us-east-1.s3" && aws_vpc_endpoint.s3[0].vpc_endpoint_type == "Gateway"
    error_message = "O endpoint deve ser do tipo Gateway para o S3 da região."
  }

  assert {
    condition     = aws_vpc_endpoint.s3[0].route_table_ids == toset(["rtb-public", "rtb-private-a", "rtb-private-b"])
    error_message = "O endpoint deve estar associado à tabela pública e às duas privadas."
  }
}

run "no_flow_logs_by_default" {
  command = plan

  assert {
    condition     = length(aws_flow_log.this) == 0 && length(aws_iam_role.flow_logs) == 0 && length(aws_cloudwatch_log_group.flow_logs) == 0
    error_message = "Por padrão não deve haver flow logs."
  }
}
