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
/*
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
  #provider_region = local.settings.region
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
}
*/

locals {
  config_tf         = data.terraform_remote_state.config.outputs
  vpn_preshared_key = "VPNDemoPassword"
}

#new
locals {
  config         = data.terraform_remote_state.config.outputs
  transit_zones  = local.config.transit_zones
  enterprise_vpc = var.enterprise_vpc
  transit_vpc    = var.transit_vpc
  settings       = var.settings
  tags           = var.settings.tags
}

# put a vpn appliance in just the first zone/subnet of the enterprise.
# But create one for each zone of the transit
resource "ibm_is_vpn_gateway" "enterprise" {
  for_each       = { for zone_number, zone in local.transit_vpc.zones : zone_number => zone }
  name           = "vpn-gateway-enterprise-${each.key}"
  resource_group = local.settings.resource_group_id
  subnet         = local.enterprise_vpc.zones[0].subnets[0].id
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
# connect vpns to each other
resource "ibm_is_vpn_gateway_connection" "enterprise_policybased" {
  for_each       = ibm_is_vpn_gateway.enterprise
  name           = each.value.name
  vpn_gateway    = each.value.id
  peer_address   = ibm_is_vpn_gateway.transit[each.key].public_ip_address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
  local_cidrs    = [local.settings.enterprise_cidr] # 
  peer_cidrs     = [local.settings.cloud_zones_cidr[each.key].cidr]
}
resource "ibm_is_vpn_gateway_connection" "transit_policybased" {
  for_each       = ibm_is_vpn_gateway.transit
  name           = each.value.name
  vpn_gateway    = each.value.id
  peer_address   = ibm_is_vpn_gateway.enterprise[each.key].public_ip_address
  preshared_key  = local.vpn_preshared_key
  admin_state_up = true
  local_cidrs    = [local.settings.cloud_zones_cidr[each.key].cidr]
  peer_cidrs     = [local.settings.enterprise_cidr]
}

#----------------------------------------------------------------------
# NOTE: Add additional address prefixes in the transit for the enterprise to allow the
# spokes to learn enterprise routes via transit gateways
locals {
  enterprise_zones = local.config_tf.enterprise_zones
  address_prefixes = local.settings.enterprise_phantom_address_prefixes_in_transit ? local.enterprise_zones : []
}
resource "ibm_is_vpc_address_prefix" "locations" {
  for_each = { for k, zone in local.address_prefixes : k => zone }
  name     = "${local.settings.basename}phantom-enterprise${each.key}"
  vpc      = local.transit_vpc.id
  zone     = each.value.zone
  cidr     = each.value.cidr
}

#----------------------------------------------------------------------
# NOTE: route traffic into the firewall.  The transit gateway is choosing the zone based on the destination address prefix.Traffic enterprise -> spokes through enterprise <-> transit gateway is routed directly to the firewall
# in same zone as the enterprise
resource "ibm_is_vpc_routing_table" "transit_tgw_ingress" {
  vpc                           = local.transit_vpc.id
  name                          = "tgw-ingress"
  route_direct_link_ingress     = false
  route_transit_gateway_ingress = true
  route_vpc_zone_ingress        = false
}

locals {
  # from the spokes into the transit destine for enterprise.  The transit VPC zone is determined
  # by either the egress route at the spoke (if provided) or by the matching address prefix in the transit vpc.
  # Either way the enterprise cidr in a zone are routed to the firewall in the transit VPC zone
  spokes_to_enterprise = { for zone_number, transit_zone in local.transit_zones : zone_number => {
    name        = "z${transit_zone.zone}-to-enterprise"
    zone        = transit_zone.zone
    zone_number = zone_number
    }
  }
}

resource "ibm_is_vpc_routing_table_route" "transit_tgw_ingress" {
  for_each      = local.spokes_to_enterprise
  vpc           = local.transit_vpc.id
  routing_table = ibm_is_vpc_routing_table.transit_tgw_ingress.routing_table
  name          = each.value.name
  zone          = each.value.zone
  destination   = local.enterprise_zones[each.value.zone_number].cidr
  #destination   = ibm_is_vpn_gateway_connection.transit_policybased[each.key].peer_cidrs[0]
  #destination = "1.0.0.0/16"
  #action   = "deliver"
  next_hop = ibm_is_vpn_gateway_connection.transit_policybased[each.key].gateway_connection
}
