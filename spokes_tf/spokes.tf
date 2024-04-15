# spokes - vpc for each spoke
data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}

data "terraform_remote_state" "transit" {
  backend = "local"

  config = {
    path = "../transit_tf/terraform.tfstate"
  }
}

locals {
  config_tf       = data.terraform_remote_state.config.outputs
  settings        = local.config_tf.settings
  provider_region = local.settings.region
  spokes_zones    = local.config_tf.spokes_zones
  tags            = local.settings.tags

  zones_subnets = [for spoke_number, spokes_zones in local.spokes_zones : [for zone_number, zone in spokes_zones : [for subnet_number, subnet in zone.subnets : {
    subnet_number = subnet_number # subnet in zone: 0,1,2,3
    zone          = subnet.zone   # us-south-1
    cidr          = subnet.cidr
    name          = subnet.name
  }]]]

  transit_vpc = data.terraform_remote_state.transit.outputs.vpc
}

module "spokes" {
  for_each                  = { for spoke, zones in local.spokes_zones : spoke => zones }
  source                    = "../modules/vpc"
  name                      = "${local.settings.basename}-spoke${each.key}"
  settings                  = local.settings
  zones_address_prefixes    = [for zone_number, zone_cidr in local.spokes_zones[each.key] : [zone_cidr]]
  zones_subnets             = local.zones_subnets[each.key]
  make_firewall_route_table = false
  hub_vpc_id                = local.transit_vpc.id
  is_hub                    = false
}

output "vpcs" {
  value = [for spoke in module.spokes : spoke.vpc]
}
