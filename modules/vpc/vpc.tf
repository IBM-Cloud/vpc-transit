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
variable "zones_address_prefixes" {} # [[{zone: "us-south-1", cidr = "10.0.0,0/16}, ...], []]"

variable "zones_subnets" {} # zones is a list of both address_prefixes and subnets

# Make a firewall route table and put the firewall subnets into the route table.  Delegate to the VPC.
# Initially this is a noop.  But will be required when the rest of the subnets egress to the firewall.  Do not want
# the firewall to route to the firewall
variable "make_firewall_route_table" {}

locals {
  name                         = var.name
  tags                         = concat(var.settings.tags, ["location:${var.name}"])
  resource_group_id            = var.settings.resource_group_id
  myip                         = var.settings.myip
  security_group_inbound_cidrs = [var.settings.cloud_cidr, var.settings.enterprise_cidr]

  # subnets are var.zone[zid].subnets[sid] convert this to a map of subnets indexed by "z$zid-s$sid"
  subnets = flatten(var.zones_subnets)

  # zones could be derived from var.zones_subnets or var.zones_address_prefixes
  zones = [for zone_number, subnets in var.zones_subnets : {
    zone = subnets[0].zone
  }]
}

resource "ibm_is_vpc" "location" {
  name                      = local.name
  resource_group            = local.resource_group_id
  address_prefix_management = "manual"
  tags                      = local.tags
}

# routing table to delegate all destinations to standard VPC routing.  Firewall subnet will use this table
resource "ibm_is_vpc_routing_table" "location" {
  count = var.make_firewall_route_table ? 1 : 0
  name  = "egress-delegate"
  vpc   = ibm_is_vpc.location.id
}

# todo default for made fw zone
resource "ibm_is_vpc_routing_table_route" "transit_policybased" {
  for_each      = var.make_firewall_route_table ? { for zone_number, zone in local.zones : zone_number => zone } : {}
  vpc           = ibm_is_vpc.location.id
  routing_table = ibm_is_vpc_routing_table.location[0].routing_table
  name          = "${local.name}-${each.key}"
  zone          = each.value.zone
  destination   = "0.0.0.0/0"
  action        = "delegate"
  next_hop      = "0.0.0.0"
}


resource "ibm_is_vpc_address_prefix" "locations" {
  for_each = { for key, address_prefix in flatten(var.zones_address_prefixes) : "${local.name}-${key}" => address_prefix }
  name     = each.key
  zone     = each.value.zone
  vpc      = ibm_is_vpc.location.id
  cidr     = each.value.cidr
}

resource "ibm_is_subnet" "locations" {
  for_each        = { for subnet in local.subnets : subnet.name => subnet }
  depends_on      = [ibm_is_vpc_address_prefix.locations]
  name            = each.value.name
  vpc             = ibm_is_vpc.location.id
  zone            = each.value.zone
  ipv4_cidr_block = each.value.cidr
  resource_group  = local.resource_group_id
  # todo the make_firewall_route_table should be make the new default route table for all but FW?
  routing_table = (var.make_firewall_route_table && each.value.subnet_number == var.settings.subnet_fw) ? ibm_is_vpc_routing_table.location[0].routing_table : null
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
  output_zones = [for zone_number, subnets in var.zones_subnets : {
    subnets = [for subnet_number, subnet in subnets : ibm_is_subnet.locations[subnet.name]]
    /*
    address_prefixes = [for address_prefix_number, address_prefix in zone.address_prefixes : ibm_is_vpc_address_prefix.locations["z${zone_number}-s${address_prefix_number}"]]
    */
  }]
}

# using default routing table
data "ibm_is_vpc_default_routing_table" "location" {
  vpc = ibm_is_vpc.location.id
}

output "vpc" {
  value = {
    id                     = ibm_is_vpc.location.id
    crn                    = ibm_is_vpc.location.crn
    name                   = ibm_is_vpc.location.name
    default_security_group = ibm_is_vpc.location.default_security_group
    # todo routing table is the default VPC egress routing table, not the one created for firewall
    #routing_table = var.make_firewall_route_table ? ibm_is_vpc_routing_table.location[0].routing_table : data.ibm_is_vpc_default_routing_table.location.default_routing_table
    routing_table = data.ibm_is_vpc_default_routing_table.location.default_routing_table
    zones = [for zone in local.output_zones : {
      subnets = [for subnet in zone.subnets : {
        id              = subnet.id
        name            = subnet.name
        ipv4_cidr_block = subnet.ipv4_cidr_block
        zone            = subnet.zone
        crn             = subnet.crn
      }]
      /* todo
      address_prefixes = [for address_prefix in zone.address_prefixes : {
        id   = address_prefix.id
        name = address_prefix.name
        cidr = address_prefix.cidr
        zone = address_prefix.zone
      }]
      */
      }
    ]
  }
}
