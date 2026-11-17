mock_provider "aws" {
  override_during = plan
}

variables {
  name               = "example-net"
  availability_zones = ["us-east-1a", "us-east-1b"]
}

run "single_nat" {
  command = plan

  variables {
    nat_gateway_mode = "single"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1
    error_message = "single deve criar um NAT e um EIP."
  }

  assert {
    condition     = length(aws_route.private_nat) == 2 && alltrue([for route in aws_route.private_nat : route.destination_cidr_block == "0.0.0.0/0"])
    error_message = "Todas as tabelas privadas devem ganhar rota padrão para o NAT."
  }

  assert {
    condition     = aws_eip.nat[0].domain == "vpc"
    error_message = "O EIP do NAT deve ser do domínio vpc."
  }
}

run "nat_per_az" {
  command = plan

  variables {
    nat_gateway_mode = "one_per_az"
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2 && length(aws_eip.nat) == 2 && length(aws_route.private_nat) == 2
    error_message = "one_per_az deve criar um NAT, um EIP e uma rota por zona."
  }
}

run "three_azs_custom_cidrs" {
  command = plan

  variables {
    cidr_block           = "10.20.0.0/20"
    availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
    public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
    private_subnet_cidrs = ["10.20.8.0/24", "10.20.9.0/24", "10.20.10.0/24"]
  }

  assert {
    condition     = aws_subnet.private[*].cidr_block == ["10.20.8.0/24", "10.20.9.0/24", "10.20.10.0/24"] && length(aws_route_table.private) == 3
    error_message = "CIDRs informados devem ser usados, com uma tabela privada por zona."
  }
}

run "s3_endpoint_disabled" {
  command = plan

  variables {
    s3_gateway_endpoint_enabled = false
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 0 && output.s3_gateway_endpoint_id == null
    error_message = "Sem o endpoint, nada deve ser criado e a saída deve ser nula."
  }
}

run "tags_everywhere" {
  command = plan

  variables {
    tags             = { service = "example" }
    nat_gateway_mode = "single"
  }

  assert {
    condition = alltrue([
      aws_vpc.this.tags["service"] == "example",
      aws_internet_gateway.this.tags["service"] == "example",
      aws_subnet.public[0].tags["service"] == "example",
      aws_subnet.private[0].tags["service"] == "example",
      aws_route_table.public.tags["service"] == "example",
      aws_route_table.private[0].tags["service"] == "example",
      aws_nat_gateway.this[0].tags["service"] == "example",
      aws_eip.nat[0].tags["service"] == "example",
      aws_vpc_endpoint.s3[0].tags["service"] == "example",
      aws_default_security_group.this.tags["service"] == "example",
    ])
    error_message = "As tags devem ir para todos os recursos que aceitam tags."
  }
}
