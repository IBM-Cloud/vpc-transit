# create the vpn related resources and route resources required by the VPN

variable "settings" {}
variable "enterprise_vpc" {}
variable "transit_vpc" {}

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}

locals {
  config_tf         = data.terraform_remote_state.config.outputs
  vpn_preshared_key = "VPNDemoPassword"
  transit_zones     = local.config_tf.transit_zones
  enterprise_vpc    = var.enterprise_vpc
  transit_vpc       = var.transit_vpc
  settings          = var.settings
  tags              = var.settings.tags
  enterprise_zones  = local.config_tf.enterprise_zones
  address_prefixes  = local.settings.enterprise_phantom_address_prefixes_in_transit ? local.enterprise_zones : []
}

#----------------------------------------------------------------------
# NOTE: Add additional address prefixes in the transit for the enterprise to allow the
# spokes to learn enterprise routes via transit gateways.  Note this puts the enterprise
# CIDRs in a specific zone.
resource "ibm_is_vpc_address_prefix" "locations" {
  for_each = { for k, zone in local.address_prefixes : k => zone }
  name     = "${local.settings.basename}phantom-enterprise${each.key}"
  vpc      = local.transit_vpc.id
  zone     = each.value.zone
  cidr     = each.value.cidr
}

# put a vpn appliance in each zone of the enterprise
resource "ibm_is_vpn_gateway" "enterprise" {
  for_each       = { for zone_number, zone in local.enterprise_vpc.zones : zone_number => zone }
  name           = "vpn-gateway-enterprise-${each.key}"
  resource_group = local.settings.resource_group_id
  subnet         = each.value.subnets[local.settings.subnet_dns].id
  mode           = local.settings.vpn_route_based ? "route" : "policy"
  tags           = local.tags
}
resource "ibm_is_vpn_gateway" "transit" {
  #for_each       = local.transit_vpc.subnets
  for_each       = { for zone_number, zone in local.transit_vpc.zones : zone_number => zone }
  name           = "vpn-gateway-transit-${each.key}"
  resource_group = local.settings.resource_group_id
  subnet         = each.value.subnets[local.settings.subnet_fw].id
  mode           = local.settings.vpn_route_based ? "route" : "policy"
  tags           = local.tags
}

locals {
  # full cross product between enterprise zone to different transit zone, notice the if statement
  partial_enterprise_cross_transit = flatten([
    for enterprise_zone_number, enterprise in ibm_is_vpn_gateway.enterprise : [
      for transit_zone_number, transit in ibm_is_vpn_gateway.transit : {
        enterprise_cidr        = local.enterprise_zones[enterprise_zone_number].cidr
        transit_cidr           = local.transit_zones[transit_zone_number].cidr
        enterprise_zone_number = enterprise_zone_number
        transit_zone_number    = transit_zone_number
      } if enterprise_zone_number != transit_zone_number
    ]
  ])
  # partial cross product, enterprise zones are mapped to cloud zones, each enterprise zone is connected to the corresponding cloud zone
  # The cloud peer cide is the entire cloud 10.0.0.0/8
  zonal_enterprise_cross_transit = flatten([
    for enterprise_zone_number, enterprise in ibm_is_vpn_gateway.enterprise : {
      enterprise_cidr        = local.enterprise_zones[enterprise_zone_number].cidr
      transit_cidr           = local.settings.cloud_cidr
      enterprise_zone_number = enterprise_zone_number
      transit_zone_number    = enterprise_zone_number
    }
  ])

  enterprise_cross_transit = concat(local.zonal_enterprise_cross_transit, local.partial_enterprise_cross_transit)
}
output "partial_enterprise_cross_transit" {
  value = local.partial_enterprise_cross_transit
}

resource "ibm_is_vpn_gateway_connection" "enterprise_policybased" {
  for_each       = { for k, v in local.enterprise_cross_transit : k => v }
  name           = "to-zone-${each.value.transit_zone_number}"
  vpn_gateway    = ibm_is_vpn_gateway.enterprise[each.value.enterprise_zone_number].id
  peer_address   = ibm_is_vpn_gateway.transit[each.value.transit_zone_number].public_ip_address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
  local_cidrs    = [each.value.enterprise_cidr]
  peer_cidrs     = [each.value.transit_cidr]
}

resource "ibm_is_vpn_gateway_connection" "transit_policybased" {
  for_each       = { for k, v in local.enterprise_cross_transit : k => v }
  name           = "to-zone-${each.value.enterprise_zone_number}"
  vpn_gateway    = ibm_is_vpn_gateway.transit[each.value.transit_zone_number].id
  peer_address   = ibm_is_vpn_gateway.enterprise[each.value.enterprise_zone_number].public_ip_address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
  local_cidrs    = [each.value.transit_cidr]
  peer_cidrs     = [each.value.enterprise_cidr]
}

#----------------------------------------------------------------------
# The accept_routes_from_resource_type == vpn_gateway will
# 1. create a route for each VPN gateway connection 
# 2. connect that route's next_hop to the active VPN gateway appliance (update next hop on fail over)
resource "ibm_is_vpc_routing_table" "transit_tgw_ingress" {
  vpc                              = local.transit_vpc.id
  name                             = "vpn-ingress"
  route_direct_link_ingress        = false
  route_transit_gateway_ingress    = true
  route_vpc_zone_ingress           = false
  accept_routes_from_resource_type = ["vpn_gateway"]
}

/*
does not work for policy VPN gateway
resource "ibm_is_vpc_routing_table_route" "transit" {
  vpc           = local.transit_vpc.id
  routing_table = local.transit_vpc.routing_table
  zone          = "us-south-1"
  name          = "kludged"
  destination   = "192.168.1.0/24"
  action        = "deliver"
  next_hop      = ibm_is_vpn_gateway_connection.transit_policybased[1].gateway_connection
}
*/


output "vpn_gateway_enterprise" {
  value = ibm_is_vpn_gateway.enterprise
}

output "vpn_gateway_transit" {
  value = ibm_is_vpn_gateway.transit
}

output "vpn_gateway_connection_enterprise" {
  value = ibm_is_vpn_gateway_connection.enterprise_policybased
}

output "vpn_gateway_connection_transit" {
  value = ibm_is_vpn_gateway_connection.transit_policybased
}


/*
        #enterprise_peer_address = ibm_is_vpn_gateway.enterprise[enterprise_zone_number].public_ip_address
        #transit_peer_address    = ibm_is_vpn_gateway.transit[transit_zone_number].public_ip_address
# connect vpns to each other
resource "ibm_is_vpn_gateway_connection" "enterprise_policybased" {
  for_each       = ibm_is_vpn_gateway.enterprise
  name           = each.value.name
  vpn_gateway    = each.value.id
  peer_address   = ibm_is_vpn_gateway.transit[each.key].public_ip_address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
  local_cidrs    = [local.enterprise_zones[each.key].cidr]
  peer_cidrs     = [local.settings.cloud_zones_cidr[each.key].cidr]
}
resource "ibm_is_vpn_gateway_connection" "transit_policybased" {
  for_each       = ibm_is_vpn_gateway.transit
  name           = each.value.name
  vpn_gateway    = each.value.id
  peer_address   = ibm_is_vpn_gateway.enterprise[each.key].public_ip_address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
  local_cidrs    = [local.enterprise_zones[each.key].cidr]
  peer_cidrs     = [local.settings.cloud_zones_cidr[each.key].cidr]
  local_cidrs    = [local.settings.cloud_zones_cidr[each.key].cidr]
  peer_cidrs     = [local.enterprise_zones[each.key].cidr]
}

# Route from the enterprise to the appropriate enterprise zonal VPN
locals {
  enterprise_routes = { for source_zone_number, source_zone in ibm_is_ibm_is_vpn_gateway.enterprise : source_zone_number => source_zone }
}
resource "ibm_is_vpc_routing_table_route" "enterprise_to_enterprise_egress" {

}


}

*/
