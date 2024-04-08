# enterprise VPC

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}

locals {
  provider_region  = local.settings.region
  config_tf        = data.terraform_remote_state.config.outputs
  enterprise_zones = local.config_tf.enterprise_zones
  settings         = local.config_tf.settings
  name             = "${local.settings.basename}-enterprise"

  zones_subnets = [for zone_number, zone in local.enterprise_zones : [for subnet_number, subnet in zone.subnets : {
    subnet_number = subnet_number # subnet in zone: 0,1,2,3
    zone          = subnet.zone   # us-south-1
    cidr          = subnet.cidr
    name          = subnet.name
  }]]
}

module "enterprise" {
  source                    = "../modules/vpc"
  name                      = local.name
  settings                  = local.settings
  zones_address_prefixes    = [for zone_number, zone_cidr in local.enterprise_zones : [zone_cidr]]
  zones_subnets             = local.zones_subnets
  make_firewall_route_table = false
  hub_vpc_id                = null
  is_hub                    = false
}

output "vpc" {
  value = module.enterprise.vpc
}
