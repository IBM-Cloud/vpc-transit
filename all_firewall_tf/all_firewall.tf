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
  transit_zones   = local.config.transit_zones
  spokes_zones    = local.config.spokes_zones

  spokes   = data.terraform_remote_state.spokes.outputs
  transit  = data.terraform_remote_state.transit.outputs
  firewall = data.terraform_remote_state.firewall.outputs

  # spoke to transit stays in the same zone for routes spoke : cloud (spoke/transit) -> firewall in zone
  spoke_egress_to_cloud = [for spoke_vpc in local.spokes.vpcs : [
    for zone_number, transit in local.firewall.zones : {
      vpc           = spoke_vpc.id                                            # spoke routing table
      routing_table = spoke_vpc.routing_table                                 # spoke routing table
      zone          = local.transit_zones[zone_number].zone                   # spoke and transit zone
      name          = "egress-cloud-${local.transit_zones[zone_number].zone}" # spoke and transit zone
      destination   = local.settings.cloud_cidr                               # all cloud cidr
      action        = "deliver"
      next_hop      = transit.firewall_ip
    }
    ]
  ]

  # transit to cloud  zone : cloud -> firewall in destination zone
  transit_egress_to_spoke = [for source_zone_number, source_zone in local.transit_zones : [
    for dest_zone_number, dest_zone in local.settings.cloud_zones_cidr : {
      vpc           = local.transit.vpc.id            # spoke routing table
      routing_table = local.transit.vpc.routing_table # spoke routing table
      zone          = source_zone.zone                # transit zone
      name          = "egress-cloud-${source_zone_number}-${dest_zone_number}"
      destination   = dest_zone.cidr
      action        = "deliver"
      next_hop      = local.firewall.zones[dest_zone_number].firewall_ip
    }
  ]]

  # transit to itsef should be handled with normal routing
  transit_egress_to_transit = [for transit_zone_number, transit in local.firewall.zones : [
    for destination_zone_number, destination_transit_zone in local.transit_zones : {
      vpc           = local.transit.vpc.id                                       # spoke routing table
      routing_table = local.transit.vpc.routing_table                            # spoke routing table
      zone          = local.transit_zones[transit_zone_number].zone              # transit zone
      name          = "except-${transit_zone_number}-${destination_zone_number}" # all cloud cidr
      destination   = destination_transit_zone.cidr                              # all cloud cidr
      action        = "delegate"
      next_hop      = "0.0.0.0"
    }
  ]]

  spoke_egress_routes = flatten(concat(local.spoke_egress_to_cloud, local.transit_egress_to_spoke, local.transit_egress_to_transit))
}

resource "ibm_is_vpc_routing_table_route" "transit_policybased" {
  for_each      = { for key, value in local.spoke_egress_routes : key => value }
  vpc           = each.value.vpc
  routing_table = each.value.routing_table
  name          = each.value.name
  zone          = each.value.zone
  destination   = each.value.destination
  action        = each.value.action
  next_hop      = each.value.next_hop
}
