/*
vpc
- address prefixes
- subnets
- instance in each worker subnet
- fip for each instance
- route table - optional
*/

variable "name" {}
variable "settings" {}
variable "zones" {}            # zones is a list of both address_prefixes and subnets
variable "make_route_table" {} # make the route table and create the subnets in the route table

locals {
  name                         = var.name
  tags                         = concat(var.settings.tags, ["location:${var.name}"])
  resource_group_id            = var.settings.resource_group_id
  myip                         = var.settings.myip
  security_group_inbound_cidrs = [var.settings.cloud_cidr, var.settings.enterprise_cidr]

  # subnets are var.zone[zid].subnets[sid] convert this to a map of subnets indexed by "z$zid-s$sid"
  flat_subnets = flatten([for zone_number, zone in var.zones : [for subnet_number, subnet in zone.subnets : {
    zone_number   = zone_number
    subnet_number = subnet_number
    subnet        = subnet
  }]])
  subnets = { for subnet in local.flat_subnets : "z${subnet.zone_number}-s${subnet.subnet_number}" => subnet }
  flat_address_prefixes = flatten([for zone_number, zone in var.zones : [for address_prefix_number, address_prefix in zone.address_prefixes : {

    # address prefixes are similar to subnets, see above
    zone_number           = zone_number
    address_prefix_number = address_prefix_number
    address_prefix        = address_prefix
  }]])
  address_prefixes = { for address_prefix in local.flat_address_prefixes : "z${address_prefix.zone_number}-s${address_prefix.address_prefix_number}" => address_prefix.address_prefix }
}

resource "ibm_is_vpc" "location" {
  name                      = local.name
  resource_group            = local.resource_group_id
  address_prefix_management = "manual"
  tags                      = local.tags
}

resource "ibm_is_vpc_routing_table" "location" {
  count = var.make_route_table ? 1 : 0
  name  = local.name
  vpc   = ibm_is_vpc.location.id
}

# todo default for made fw zone
resource "ibm_is_vpc_routing_table_route" "transit_policybased" {
  for_each      = var.make_route_table ? { for zone_number, zone in var.zones : zone_number => zone } : {}
  vpc           = ibm_is_vpc.location.id
  routing_table = ibm_is_vpc_routing_table.location[0].routing_table
  name          = "${local.name}-${each.key}"
  zone          = each.value.zone
  destination   = "0.0.0.0/0"
  action        = "delegate"
  next_hop      = "0.0.0.0"
}


resource "ibm_is_vpc_address_prefix" "locations" {
  for_each = local.address_prefixes
  name     = "${local.name}-${each.key}"
  zone     = each.value.zone
  vpc      = ibm_is_vpc.location.id
  cidr     = each.value.cidr
}

resource "ibm_is_subnet" "locations" {
  for_each        = local.subnets
  depends_on      = [ibm_is_vpc_address_prefix.locations]
  name            = "${local.name}-${each.key}"
  vpc             = ibm_is_vpc.location.id
  zone            = each.value.subnet.zone
  ipv4_cidr_block = each.value.subnet.cidr
  resource_group  = local.resource_group_id
  # todo the make_route_table should be make the new default route table for all but FW?
  routing_table = (var.make_route_table && each.value.subnet_number == var.settings.subnet_fw) ? ibm_is_vpc_routing_table.location[0].routing_table : null
}

resource "ibm_is_security_group_rule" "inbound_myip" {
  group     = ibm_is_vpc.location.default_security_group
  direction = "inbound"
  remote    = local.myip
  tcp {
    port_min = 22
    port_max = 22
  }
}
resource "ibm_is_security_group_rule" "inbound_remote_cidr" {
  for_each  = toset(local.security_group_inbound_cidrs)
  group     = ibm_is_vpc.location.default_security_group
  direction = "inbound"
  remote    = each.value
}

locals {
  zones = [for zone_number, zone in var.zones : {
    subnets          = [for subnet_number, subnet in zone.subnets : ibm_is_subnet.locations["z${zone_number}-s${subnet_number}"]]
    address_prefixes = [for address_prefix_number, address_prefix in zone.address_prefixes : ibm_is_vpc_address_prefix.locations["z${zone_number}-s${address_prefix_number}"]]
  }]
}

# using default routing table
data "ibm_is_vpc_default_routing_table" "location" {
  vpc = ibm_is_vpc.location.id
}

output "vpc" {
  value = {
    id   = ibm_is_vpc.location.id
    crn  = ibm_is_vpc.location.crn
    name = ibm_is_vpc.location.name
    # todo routing table is the default VPC egress routing table, not the one created for firewall
    #routing_table = var.make_route_table ? ibm_is_vpc_routing_table.location[0].routing_table : data.ibm_is_vpc_default_routing_table.location.default_routing_table
    routing_table = data.ibm_is_vpc_default_routing_table.location.default_routing_table
    zones = [for zone in local.zones : {
      subnets = [for subnet in zone.subnets : {
        id              = subnet.id
        name            = subnet.name
        ipv4_cidr_block = subnet.ipv4_cidr_block
        zone            = subnet.zone
        crn             = subnet.crn
      }]
      address_prefixes = [for address_prefix in zone.address_prefixes : {
        id   = address_prefix.id
        name = address_prefix.name
        cidr = address_prefix.cidr
        zone = address_prefix.zone
      }]
      }
    ]
  }
}
