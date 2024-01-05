# firewall.tf to create the firewall and the other stuff required to route data through the firewall.
# - firewall instances and possibly associated network load balancer
# - vpc ingress route table and routes

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
  cloud_zones_cidr  = local.settings.cloud_zones_cidr
  transit_vpc       = data.terraform_remote_state.transit.outputs.vpc
  enterprise_zones  = local.config_tf.enterprise_zones
  transit_zones     = local.config_tf.transit_zones
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


# all in and out
resource "ibm_is_security_group" "zone" {
  resource_group = local.settings.resource_group_id
  name           = "${local.name}-inall-outall"
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

# port 22 in and all out
resource "ibm_is_security_group" "zone_22" {
  resource_group = local.settings.resource_group_id
  name           = "${local.name}-in22-outall"
  vpc            = local.transit_vpc.id
}

# todo tighten these up, see test instances
resource "ibm_is_security_group_rule" "zone_22_inbound_22" {
  group     = ibm_is_security_group.zone_22.id
  direction = "inbound"
  udp {
    port_min = 22
    port_max = 22
  }
}
resource "ibm_is_security_group_rule" "zone_22_outbound_all" {
  group     = ibm_is_security_group.zone_22.id
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
  ssh_key_ids                  = local.settings.ssh_key_ids
  name                         = "${local.name}-z${tonumber(each.key) + 1}-s${local.settings.subnet_fw}"
  firewall_nlb                 = local.settings.firewall_nlb
  number_of_firewalls_per_zone = local.settings.firewall_nlb ? local.settings.number_of_firewalls_per_zone : 1
  user_data                    = local.user_data
  security_groups              = [ibm_is_security_group.zone.id]
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

resource "null_resource" "vpc-routing-table-update" {
  triggers = {
    path_module   = path.module
    vpc           = local.transit_vpc.id
    routing_table = ibm_is_vpc_routing_table.transit_tgw_ingress.routing_table
    region        = local.settings.region
  }
  provisioner "local-exec" {
    command = <<-EOS
      vpc=${self.triggers.vpc} \
      routing_table=${self.triggers.routing_table} \
      region=${self.triggers.region} \
      ${self.triggers.path_module}/../../bin/vpc-routing-table-update.sh create
    EOS
  }
}

locals {
  # from the spokes into the transit destine for enterprise.  The transit VPC zone is determined
  # by either the egress route at the spoke (if provided) or by the matching address prefix in the transit vpc.
  # Either way the enterprise cidr in a zone are routed to the firewall in the transit VPC zone
  spokes_to_enterprise = [for zone_number, transit_zone in local.transit_zones : {
    name        = "z${transit_zone.zone}-to-enterprise"
    zone        = transit_zone.zone
    cidr        = local.settings.enterprise_cidr
    zone_number = zone_number
    }
  ]

  # zone specific routes.
  zone_ingress_routes = [for zone_number, zone_cidr in local.cloud_zones_cidr : {
    name        = "z${zone_number}-entire-zone"
    zone        = zone_cidr.zone
    cidr        = zone_cidr.cidr
    zone_number = zone_number
    }
  ]

  routes = flatten(concat(local.spokes_to_enterprise, local.zone_ingress_routes))
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

resource "null_resource" "vpc-routing-table-route-create" {
  for_each = ibm_is_vpc_routing_table_route.transit_tgw_ingress
  triggers = {
    path_module   = path.module
    vpc           = each.value.vpc
    routing_table = each.value.routing_table
    route         = each.value.route_id
    region        = local.settings.region
  }
  provisioner "local-exec" {
    command = <<-EOS
      vpc=${self.triggers.vpc} \
      routing_table=${self.triggers.routing_table} \
      route=${self.triggers.route} \
      region=${self.triggers.region} \
      ${self.triggers.path_module}/../../bin/vpc-routing-table-route-update.sh create
    EOS
  }
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
