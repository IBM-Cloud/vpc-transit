variable "ibmcloud_api_key" {}

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}

locals {
  config_tf        = data.terraform_remote_state.config.outputs
  settings         = local.config_tf.settings
  provider_region  = local.settings.region
  transit_zones    = local.config_tf.transit_zones
  cloud_zones_cidr = local.settings.cloud_zones_cidr
  tags             = local.settings.tags

  zones_subnets = [for zone_number, zone in local.transit_zones : [for subnet_number, subnet in zone.subnets : {
    subnet_number = subnet_number # subnet in zone: 0,1,2,3
    zone          = subnet.zone   # us-south-1
    cidr          = subnet.cidr
    name          = "${local.settings.basename}-transit-z${zone_number}-s${subnet_number}"
  }]]
}

module "transit" {
  source                    = "../modules/vpc"
  name                      = "${local.settings.basename}-transit"
  settings                  = local.settings
  zones_address_prefixes    = [for zone_number, zone_cidr in local.cloud_zones_cidr : [zone_cidr]]
  zones_subnets             = local.zones_subnets
  make_firewall_route_table = true
}


output "vpc" {
  value = module.transit.vpc
}
