# firewall.tf to create the firewall and the other stuff required to route data through the firewall.
# - firewall instances and possibly associated network load balancer
# - vpc ingress route table and routes


# todo remove
# - vpc address filter to advertise routes through the transit vpc

# todo
# - prefix filters to avoid leaking the address filters

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
data "terraform_remote_state" "enterprise_link" {
  backend = "local"

  config = {
    path = "../enterprise_link_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "transit_spoke_tgw" {
  backend = "local"

  config = {
    path = "../transit_spoke_tgw_tf/terraform.tfstate"
  }
}

locals {
  config_tf         = data.terraform_remote_state.config.outputs
  settings          = local.config_tf.settings
  provider_region   = local.settings.region
  tags              = local.settings.tags
  transit_vpc       = data.terraform_remote_state.transit.outputs.vpc
  enterprise_zones  = local.config_tf.enterprise_zones
  transit_zones     = local.config_tf.transit_zones
  spokes_zones      = local.config_tf.spokes_zones
  enterprise_vpc    = data.terraform_remote_state.enterprise.outputs.vpc
  enterprise_link   = data.terraform_remote_state.enterprise_link.outputs
  transit_spoke_tgw = data.terraform_remote_state.transit_spoke_tgw.outputs
  name              = "${local.settings.basename}-fw"

  user_data = <<-EOT
  #!/bin/bash
  set -x
  export DEBIAN_FRONTEND=noninteractive
  apt -qq -y update < /dev/null
  apt -qq -y install net-tools nginx npm < /dev/null
  EOT
}


resource "ibm_is_security_group" "zone" {
  resource_group = local.settings.resource_group_id
  name           = local.name
  vpc            = local.transit_vpc.id
}

# todo tighten these up, see test instances
resource "ibm_is_security_group_rule" "zone_inbound_all" {
  group     = ibm_is_security_group.zone.id
  direction = "inbound"
}
resource "ibm_is_security_group_rule" "zone_outbound_all" {
  group     = ibm_is_security_group.zone.id
  direction = "outbound"
}

# one load balanced firewall for each zone,  It is in the transit vpc in the subnet reserved for firewall
module "transit_zones" {
  for_each                     = { for zone_number, zone in local.transit_vpc.zones : zone_number => zone }
  source                       = "./firewall_zone_tf"
  tags                         = local.tags
  vpc_id                       = local.transit_vpc.id
  subnet_firewall              = each.value.subnets[local.settings.subnet_fw]
  resource_group_id            = local.settings.resource_group_id
  image_id                     = local.settings.image_id
  profile                      = local.settings.profile
  ssh_key_ids                  = [local.settings.ssh_key.id]
  name                         = "${local.name}-z${each.key}-s${local.settings.subnet_fw}"
  firewall_nlb                 = local.settings.firewall_nlb
  number_of_firewalls_per_zone = local.settings.firewall_nlb ? local.settings.number_of_firewalls_per_zone : 1
  user_data                    = local.user_data
  security_groups              = [ibm_is_security_group.zone.id]
}

#----------------------------------------------------------------------
# NOTE: Add additional address prefixes to allow the transit gateways to learn routes.  These address prefixes
# cover the entire zones (not specific vpc subnets)
# - spokes need routes to the enterprise
# - enterprise need routes to the spokes
locals {
  # todo
  #address_prefixes = concat(flatten(local.spokes_zones), local.enterprise_zones)
  address_prefixes = local.enterprise_zones
}
resource "ibm_is_vpc_address_prefix" "locations" {
  for_each = { for k, zone in local.address_prefixes : k => zone }
  name     = "${local.settings.basename}fake${each.key}"
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
  spokes_to_enterprise = [for zone_number, transit_zone in local.transit_zones : {
    name = "z${transit_zone.zone}-to-enterprise"
    zone = transit_zone.zone
    # todo cidr        = local.settings.enterprise_cidr
    cidr        = "0.0.0.0/0"
    zone_number = zone_number
    }
  ]

  /*
  # From the enterprise to the spokes.  Avoid matching the transit VPC zones by creating a route for
  # each spoke zone.  The Transit Gateway will determine the transit VPC zone based on the spoke
  # address prefixes.  Select the firewall (zone_number) in the transit zone.
  enterprise_to_spokes = flatten([for spoke, zones in local.spokes_zones : [
    for zone_number, spoke_zone in zones : {
      name        = "z${spoke_zone.zone}-to-spoke-${zone_number}"
      zone        = spoke_zone.zone
      cidr        = spoke_zone.cidr
      zone_number = zone_number
    }
  ]])
  */

  # todo
  # routes = flatten(concat(local.enterprise_to_spokes, local.spokes_to_enterprise))
  routes = flatten(local.spokes_to_enterprise)

}

resource "ibm_is_vpc_routing_table_route" "transit_tgw_ingress" {
  for_each      = { for key, value in local.routes : key => value }
  vpc           = local.transit_vpc.id
  routing_table = ibm_is_vpc_routing_table.transit_tgw_ingress.routing_table
  name          = "${each.value.name}-${each.key}"
  zone          = each.value.zone
  destination   = each.value.cidr
  action        = "deliver"
  next_hop      = module.transit_zones[each.value.zone_number].firewall_ip
}

locals {
  egress_to_firewall = [for zone_number, firewall in local.firewall_zones : {
    zone        = firewall.zone # spoke and transit zone
    name        = "egress-transit-${zone_number}"
    destination = "0.0.0.0/0"
    action      = "deliver"
    next_hop    = firewall.firewall_ip
    }
  ]

  firewall_zones = { for zone_number, tz in module.transit_zones : zone_number => {
    zone_number = zone_number
    zone        = tz.zone
    firewall_ip = tz.firewall_ip
    firewalls = { for fw_key, fw in tz.firewalls : fw_key => {
      id                   = fw.id
      name                 = fw.name
      subnet_name          = fw.name
      fip                  = fw.fip
      zone                 = fw.zone
      primary_ipv4_address = fw.primary_ipv4_address
  } } } }
}
output "zones" {
  value = local.firewall_zones
}
output "ingress_route_table" {
  value = {
    routing_table = ibm_is_vpc_routing_table.transit_tgw_ingress.routing_table
  }
}
