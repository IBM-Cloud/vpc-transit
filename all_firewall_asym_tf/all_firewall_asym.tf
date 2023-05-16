# spokes_egress for adding egress routes to the spokes

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
  spoke_to_spoke_lower_zone = local.settings.all_firewall ? [for spoke_number, spoke_vpc in local.spokes.vpcs : [
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
  ] : []

  # todo
  # Transit will allow the transit gateway to select the spoke zone based on the spoke destination address.
  # The spoke must route traffic directly to the transit zone of the transit destination (the default).
  # But, above cloud addresses for the spoke was adjusted to stay in the spoke's source zone
  # more exact routes are required to override this for the transit.
  spoke_to_transit_zone = [for spoke_number, spoke_vpc in local.spokes.vpcs : [
    for spoke_zone_number, spoke_zone in spoke_vpc.zones : [
      for transit_zone_number, transit in local.firewall.zones : {
        vpc           = spoke_vpc.id
        routing_table = spoke_vpc.routing_table
        zone          = local.settings.cloud_zones_cidr[spoke_zone_number].zone
        name          = "egress-zone-to-transit-s${spoke_number}-sz${spoke_zone_number}-dz${transit_zone_number}"
        destination   = local.transit_zones[transit_zone_number].cidr
        action        = "delegate"
        next_hop      = "0.0.0.0"
        # todo
        #action        = "deliver"
        #next_hop      = transit.firewall_ip
    }]
  ]]

  asymmetric_routing_fixes = local.settings.all_firewall ? flatten(concat(local.spoke_to_spoke_lower_zone, local.spoke_to_transit_zone)) : []
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
