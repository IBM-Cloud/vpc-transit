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

  # In the egress zones provide more exact routes to the destination zones.
  # stays in the same zone for routes spoke : cloud (spoke/transit) -> firewall in zone
  spoke_to_spoke_lower_zone = [for spoke_number, spoke_vpc in local.spokes.vpcs : [
    for source_zone_number in range(local.settings.zones) : [
      for dest_zone_number in range(0, source_zone_number) : {
        vpc           = spoke_vpc.id
        routing_table = spoke_vpc.routing_table
        zone          = local.settings.cloud_zones_cidr[source_zone_number].zone # upper zone
        name          = "egress-zone-to-lower-sz${source_zone_number}-dz${dest_zone_number}"
        destination   = local.settings.cloud_zones_cidr[dest_zone_number].cidr # lower zone
        action        = "deliver"
        next_hop      = local.firewall.zones[dest_zone_number].firewall_ip
      }
    ]]
  ]

  # in transit to lower zone
  transit_to_transit_lower_zone = [for source_zone_number in range(local.settings.zones) : [
    for dest_zone_number in range(0, source_zone_number) : {
      vpc           = local.transit.vpc.id
      routing_table = local.transit.vpc.routing_table
      zone          = local.settings.cloud_zones_cidr[source_zone_number].zone # upper zone
      name          = "egress-zone-to-lower-${source_zone_number}-to-${dest_zone_number}"
      destination   = local.settings.cloud_zones_cidr[dest_zone_number].cidr # lower zone
      action        = "deliver"
      next_hop      = local.firewall.zones[dest_zone_number].firewall_ip
    }
  ]]

  # todo remove
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

  # todo
  #spoke_egress_routes = flatten(concat(local.spoke_egress_to_cloud, local.spoke_to_spoke, local.transit_egress_to_cloud, local.transit_egress_to_lower_zone, local.transit_egress_to_transit))
  asymmetric_routing_fixes = flatten(concat(local.transit_to_transit_lower_zone, local.spoke_to_spoke_lower_zone))
}

resource "ibm_is_vpc_routing_table_route" "transit_policybased" {
  for_each      = { for key, value in local.asymmetric_routing_fixes : key => value }
  vpc           = each.value.vpc
  routing_table = each.value.routing_table
  name          = each.value.name
  zone          = each.value.zone
  destination   = each.value.destination
  action        = each.value.action
  next_hop      = each.value.next_hop
}

output "routes" {
  value = ibm_is_vpc_routing_table_route.transit_policybased
}
