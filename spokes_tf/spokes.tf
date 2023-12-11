# spokes - vpc for each spoke

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
  spokes_zones     = local.config_tf.spokes_zones
  spokes_zones_vpc = local.config_tf.spokes_zones_vpc
  tags             = local.settings.tags

  zones_subnets = [for spoke_number, spokes_zones in local.spokes_zones : [for zone_number, zone in spokes_zones : [for subnet_number, subnet in zone.subnets : {
    subnet_number = subnet_number # subnet in zone: 0,1,2,3
    zone          = subnet.zone   # us-south-1
    cidr          = subnet.cidr
    name          = "${local.settings.basename}-spoke${spoke_number}-z${zone_number + 1}-s${subnet_number}"
  }]]]
}

# VPC spokes
module "spokes" {
  for_each                  = { for spoke, zones in local.spokes_zones_vpc : spoke => zones }
  source                    = "../modules/vpc"
  name                      = "${local.settings.basename}-spoke${each.key}"
  settings                  = local.settings
  zones_address_prefixes    = each.value
  zones_subnets             = local.zones_subnets[each.key]
  make_firewall_route_table = false
}

output "vpcs" {
  value = [for spoke in module.spokes : spoke.vpc]
}
