# create the vpn related resources and route resources required by the VPN

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "enterprise" {
  backend = "local"

  config = {
    path = "../enterprise_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "transit" {
  backend = "local"

  config = {
    path = "../transit_tf/terraform.tfstate"
  }
}

locals {
  provider_region = local.settings.region
  enterprise      = data.terraform_remote_state.config.outputs.enterprise
  transit         = data.terraform_remote_state.config.outputs.transit
  spokes          = data.terraform_remote_state.config.outputs.spokes
  settings        = data.terraform_remote_state.config.outputs.settings
  tags            = local.settings.tags
  enterprise_vpc  = data.terraform_remote_state.enterprise.outputs.vpc
  transit_vpc     = data.terraform_remote_state.transit.outputs.vpc

  // indexed by the same key as the associated vpn but vpn_gateway_X[key] will be the active member with valid .address and .private_address
  vpn_gateway_enterprise_active_member = { for key, vpngw in ibm_is_vpn_gateway.enterprise : key => [for member in vpngw.members : member if member.role == "active"][0] }
  vpn_gateway_transit_active_member    = { for key, vpngw in ibm_is_vpn_gateway.transit : key => [for member in vpngw.members : member if member.role == "active"][0] }

  vpn_preshared_key = "VPNDemoPassword"
}

# put a vpn appliance in each zone (subnet)
resource "ibm_is_vpn_gateway" "enterprise" {
  for_each       = local.enterprise_vpc.subnets
  name           = each.value.name
  resource_group = local.settings.resource_group_id
  subnet         = each.value.id
  mode           = local.settings.vpn_route_based ? "route" : "policy"
  tags           = local.tags
}
resource "ibm_is_vpn_gateway" "transit" {
  for_each       = local.transit_vpc.subnets
  name           = each.value.name
  resource_group = local.settings.resource_group_id
  subnet         = each.value.id
  mode           = local.settings.vpn_route_based ? "route" : "policy"
  tags           = local.tags
}

###### POLICY BASED ##################
# connect vpns to each other
resource "ibm_is_vpn_gateway_connection" "enterprise_policybased" {
  for_each       = local.settings.vpn_route_based ? {} : ibm_is_vpn_gateway.enterprise
  name           = each.value.name
  vpn_gateway    = each.value.id
  peer_address   = local.vpn_gateway_transit_active_member[each.key].address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
  local_cidrs    = [local.enterprise.subnets[each.key].cidr] # cidr/zone of the enterprise appliance
  peer_cidrs     = [local.settings.cloud_cidr]               # remote cidr is the entire cloud
}
resource "ibm_is_vpn_gateway_connection" "transit_policybased" {
  for_each       = local.settings.vpn_route_based ? {} : ibm_is_vpn_gateway.transit
  name           = each.value.name
  vpn_gateway    = each.value.id
  peer_address   = local.vpn_gateway_enterprise_active_member[each.key].address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
  local_cidrs    = [local.settings.cloud_cidr]               # cidr/zone of the entire cloud
  peer_cidrs     = [local.enterprise.subnets[each.key].cidr] # remote cidr matches exactly the entreprise in the zone
}

# The policy based VPN has automatically initialized the default egress route table to match the peer_cidrs. Simple two zone example:
#
# Enterprise:
# Dallas 1 | 10.0.0.0/8 | VPN Dallas 1
# Dallas 2 | 10.0.0.0/8 | VPN Dallas 2
#
# Transit:
# Dallas 1 | 192.168.0.0/24 | VPN Dallas 1
# Dallas 2 | 192.168.1.0/24 | VPN Dallas 2
#
#
# Enterprise: default egress routing table is good, all cloud addresses through the vpn appliance that is in the same zone.
#
# Transit: default egress routing table has only set up 1/2 of the routes needed:
# each transit zone has an entry for the enterprise of the same zone:
#
# Missing the cross zone entries:
# Dallas 1 | 192.168.1.0/24 | VPN Dallas 2
# Dallas 2 | 192.168.0.0/24 | VPN Dallas 1

locals {
  transit_routes = local.settings.vpn_route_based ? [] : flatten([
    for tkey, tsubnet in local.transit.subnets : [
      for ekey, esubnet in local.enterprise.subnets : {
        name         = "${tsubnet.zone}-${esubnet.zone}"
        t_zone       = tsubnet.zone
        e_zone       = esubnet.zone
        e_cidr       = esubnet.cidr
        e_zone_index = ekey
      }
    ]
  ])
  transit_missing_routes = [for route in local.transit_routes : route if route.t_zone != route.e_zone]
}

resource "ibm_is_vpc_routing_table_route" "transit_policybased" {
  for_each      = { for key, value in local.transit_missing_routes : key => value }
  vpc           = local.transit_vpc.id
  routing_table = local.transit_vpc.routing_table
  name          = each.value.name
  zone          = each.value.t_zone
  destination   = each.value.e_cidr
  action        = "deliver"
  next_hop      = local.vpn_gateway_transit_active_member[each.value.e_zone_index].private_address
}

# Traffic from spokes through the transit gateway towards the enterprise need to be routed directly to the transit VPN appliances
# in same zone as destination
resource "ibm_is_vpc_routing_table" "transit_tgw_ingress" {
  vpc                           = local.transit_vpc.id
  name                          = "tgw-ingress-from-spoke"
  route_direct_link_ingress     = false
  route_transit_gateway_ingress = true
  route_vpc_zone_ingress        = false
}

resource "ibm_is_vpc_routing_table_route" "transit_tgw_ingress" {
  for_each      = { for key, value in local.transit_routes : key => value }
  vpc           = local.transit_vpc.id
  routing_table = ibm_is_vpc_routing_table.transit_tgw_ingress.routing_table
  name          = each.value.name
  zone          = each.value.t_zone
  destination   = each.value.e_cidr
  action        = "deliver"
  next_hop      = local.vpn_gateway_transit_active_member[each.value.e_zone_index].private_address
}

output "vpn" {
  value = {
    transit = {
      vpn_gateways = { for key, value in ibm_is_vpn_gateway.transit : key => {
        zone       = local.enterprise_vpc.subnets[key].zone
        name       = value.name
        peer_cidrs = local.settings.vpn_route_based ? [local.enterprise.cidr] : ibm_is_vpn_gateway_connection.transit_policybased[key].peer_cidrs
        # private_address = value.members[0].private_address
        private_address = local.vpn_gateway_transit_active_member[key].private_address
      } }
    }
  }
}

/*******

Messed a bit, but not working and not tested

locals {
  gateway_connections = zipmap(range(length(local.matching_appliance_addresses)), local.matching_appliance_addresses)
  matching_appliance_addresses = flatten([for key, value in ibm_is_vpn_gateway.enterprise : [
    {
      member_id          = 0
      vpn_gateway_key    = key
      enterprise_address = value.public_ip_address == "0.0.0.0" ? value.public_ip_address2 : value.public_ip_address
      transit_address    = ibm_is_vpn_gateway.transit[key].public_ip_address == "0.0.0.0" ? ibm_is_vpn_gateway.transit[key].public_ip_address2 : ibm_is_vpn_gateway.transit[key].public_ip_address
    }
  ]])
}

output "gateway_connections" {
  value = local.gateway_connections
}


###### ROUTE BASED ##################
# connect vpns to each other
resource "ibm_is_vpn_gateway_connection" "enterprise" {
  for_each       = local.settings.vpn_route_based ? local.gateway_connections : {}
  name           = "${ibm_is_vpn_gateway.enterprise[each.value.vpn_gateway_key].name}-${each.value.member_id}"
  vpn_gateway    = ibm_is_vpn_gateway.enterprise[each.value.vpn_gateway_key].id
  peer_address   = each.value.transit_address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
}
resource "ibm_is_vpn_gateway_connection" "transit" {
  for_each       = local.settings.vpn_route_based ? local.gateway_connections : {}
  name           = "${ibm_is_vpn_gateway.transit[each.value.vpn_gateway_key].name}-${each.value.member_id}"
  vpn_gateway    = ibm_is_vpn_gateway.transit[each.value.vpn_gateway_key].id
  peer_address   = each.value.enterprise_address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
}

# route enterprise to the vpn closest to the destination
locals {
  to_closest_destination = flatten([for enterprise_key, enterprise_subnet in local.enterprise_vpc.subnets : [
    for subnet_key, subnet_value in local.settings.cloud_zone_cidr : {
      name        = "${enterprise_subnet.name}-to-${subnet_value.zone}"
      zone        = enterprise_subnet.zone
      destination = subnet_value.cidr
      # key for both the gateway and gateway_connection
      next_hop_key = subnet_key
    }
  ]])
  enterprise_routes = zipmap(range(length(local.to_closest_destination)), local.to_closest_destination)
}

resource "ibm_is_vpc_routing_table_route" "enterprise" {
  for_each      = local.settings.vpn_route_based ? local.enterprise_routes : {}
  vpc           = local.enterprise_vpc.id
  routing_table = local.enterprise_vpc.routing_table
  zone          = each.value.zone
  name          = each.value.name
  destination   = each.value.destination
  action        = "deliver"
  next_hop      = ibm_is_vpn_gateway_connection.enterprise[each.value.next_hop_key].gateway_connection
}

# route transit to the vpn closest to the source
locals {
  route_enterprise_zones = local.settings.vpn_route_based ? local.enterprise_vpc.subnets : {}
  to_closest_source = flatten([
    for subnet_key, subnet_value in local.transit_vpc.subnets : [
      for enterprise_key, enterprise_subnet in local.route_enterprise_zones : {
        name        = "${subnet_value.name}-to-${enterprise_subnet.name}"
        zone        = subnet_value.zone
        destination = enterprise_subnet.ipv4_cidr_block
        next_hop    = ibm_is_vpn_gateway_connection.transit[subnet_key].gateway_connection
    }]
  ])
  transit_routes = zipmap(range(length(local.to_closest_source)), local.to_closest_source)
}
resource "ibm_is_vpc_routing_table_route" "transit" {
  for_each      = local.settings.vpn_route_based ? local.transit_routes : {}
  vpc           = local.transit_vpc.id
  routing_table = local.transit_vpc.routing_table
  zone          = each.value.zone
  name          = each.value.name
  destination   = each.value.destination
  action        = "deliver"
  next_hop      = each.value.next_hop
}

****/
