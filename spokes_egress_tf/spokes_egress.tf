# spokes_egress for adding egress routes to the spokes

variable "ibmcloud_api_key" {}

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "spokes" {
  backend = "local"

  config = {
    path = "../spokes_tf/terraform.tfstate"
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
  provider_region = local.settings.region
  config          = data.terraform_remote_state.config.outputs
  settings        = local.config.settings
  spokes          = data.terraform_remote_state.spokes.outputs
  transit         = data.terraform_remote_state.transit.outputs
  firewall        = data.terraform_remote_state.firewall.outputs


  # spoke -> enterprise traffic flows through the transit firewall in the same zone as the spoke initiator
  spoke_egress_to_enterprise = [for spoke_vpc in local.spokes.vpcs : [
    for zone_number, transit in local.firewall.zones : {
      vpc           = spoke_vpc                                    # spoke routing table
      routing_table = spoke_vpc.routing_table                      # spoke routing table
      zone          = local.config.transit_zones[zone_number].zone # spoke and transit zone
      name          = local.config.transit_zones[zone_number].zone # spoke and transit zone
      destination   = local.settings.enterprise_cidr               # all enterprise cidr
      next_hop      = transit.firewall_ip
    }
    ]
  ]
  spoke_egress_routes = flatten(local.spoke_egress_to_enterprise)
}

resource "ibm_is_vpc_routing_table_route" "spoke_to_enterprise_via_same_zone_firewall" {
  for_each      = { for key, value in local.spoke_egress_routes : key => value }
  vpc           = each.value.vpc.id
  routing_table = each.value.routing_table
  name          = each.value.name
  zone          = each.value.zone
  destination   = each.value.destination
  action        = "deliver"
  next_hop      = each.value.next_hop
}

output "routes" {
  value = ibm_is_vpc_routing_table_route.spoke_to_enterprise_via_same_zone_firewall
}
