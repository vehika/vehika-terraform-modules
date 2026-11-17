module "network" {
  source = "../../vpc"

  name               = var.name
  availability_zones = var.availability_zones
  nat_gateway_mode   = var.nat_gateway_mode
  tags               = var.tags
}
