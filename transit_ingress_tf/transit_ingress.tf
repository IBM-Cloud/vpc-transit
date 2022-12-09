# transit ingress routes:  traffic to the transit VPC is delivered via normal VPC routing - do not go to the firewall/router

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
data "terraform_remote_state" "firewall" {
  backend = "local"

  config = {
    path = "../firewall_tf/terraform.tfstate"
  }
}

locals {
  config          = data.terraform_remote_state.config.outputs
  settings        = local.config.settings
  provider_region = local.settings.region
  transit_zones   = local.config.transit_zones
  transit         = data.terraform_remote_state.transit.outputs
  transit_vpc     = local.transit.vpc
  firewall        = data.terraform_remote_state.firewall.outputs

  transit_ingress_delegate = [for zone_number, zone in local.transit_zones : {
    vpc           = local.transit_vpc.id
    routing_table = local.firewall.ingress_route_table.routing_table
    zone          = zone.zone
    name          = "${zone.zone}-delegate"
    action        = "delegate"
    destination   = zone.cidr
    next_hop      = "0.0.0.0"
    }
  ]
  routes = local.settings.all_firewall ? [] : local.transit_ingress_delegate
}

resource "ibm_is_vpc_routing_table_route" "transit_ingress" {
  for_each      = { for key, value in local.routes : key => value }
  vpc           = each.value.vpc
  routing_table = each.value.routing_table
  name          = each.value.name
  zone          = each.value.zone
  destination   = each.value.destination
  action        = each.value.action
  next_hop      = each.value.next_hop
}

output "routes" {
  value = ibm_is_vpc_routing_table_route.transit_ingress
}
