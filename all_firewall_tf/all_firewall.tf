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
data "terraform_remote_state" "transit_ingress" {
  backend = "local"

  config = {
    path = "../transit_ingress_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "firewall" {
  backend = "local"

  config = {
    path = "../firewall_tf/terraform.tfstate"
  }
}


locals {
  config          = data.terraform_remote_state.config.outputs
  settings        = local.config.settings
  provider_region = local.settings.region
  transit_zones   = local.config.transit_zones
  spokes_zones    = local.config.spokes_zones

  spokes          = data.terraform_remote_state.spokes.outputs
  transit         = data.terraform_remote_state.transit.outputs
  firewall        = data.terraform_remote_state.firewall.outputs
  transit_ingress = data.terraform_remote_state.transit_ingress.outputs

  # transit egress all cloud and all enterprise to firewall
  transit_egress = [for firewall_zone_number, firewall_zone in local.firewall.zones : [
    {
      vpc           = local.transit.vpc.id            # spoke routing table
      routing_table = local.transit.vpc.routing_table # spoke routing table
      zone          = firewall_zone.zone              # transit zone
      name          = "to-cloud-from-z${firewall_zone_number}"
      destination   = local.settings.cloud_cidr
      action        = "deliver"
      next_hop      = firewall_zone.firewall_ip
    },
    {
      vpc           = local.transit.vpc.id            # spoke routing table
      routing_table = local.transit.vpc.routing_table # spoke routing table
      zone          = firewall_zone.zone              # transit zone
      name          = "to-enterprise-from-z${firewall_zone_number}"
      destination   = local.settings.enterprise_cidr
      action        = "deliver"
      next_hop      = firewall_zone.firewall_ip
    }
    ]
  ]

  # transit egress to transit CIDRs do not go to firewall
  transit_egress_self_delegate = [for source_zone_number, source_zone in local.settings.cloud_zones_cidr :
    [for dest_zone_number, dest_zone in local.transit_zones : {
      vpc           = local.transit.vpc.id            # spoke routing table
      routing_table = local.transit.vpc.routing_table # spoke routing table
      zone          = source_zone.zone                # transit zone
      name          = "egress-delegate-from-${source_zone_number}-to-${dest_zone_number}"
      destination   = dest_zone.cidr
      action        = "delegate"
      next_hop      = "0.0.0.0"
    }]
  ]

  # egress spoke -> cloud (spoke or transit) from all spokes to transit
  spoke_egress_to_cloud = [for spoke_vpc in local.spokes.vpcs : [
    for firewall_zone_number, firewall_zone in local.firewall.zones : {
      vpc           = spoke_vpc.id                      # spoke routing table
      routing_table = spoke_vpc.routing_table           # spoke routing table
      zone          = firewall_zone.zone                # spoke and transit zone
      name          = "to-cloud-z${firewall_zone.zone}" # spoke and transit zone
      destination   = local.settings.cloud_cidr         # all cloud cidr
      action        = "deliver"
      next_hop      = firewall_zone.firewall_ip
    }
  ]]

  # spoke egress to same spoke CIDRs do not go to firewall
  spoke_egress_self_delegate = [for spoke_number, spoke_vpc in local.spokes.vpcs : [
    [for source_zone_number, source_zone in local.spokes_zones[spoke_number] :
      [for dest_zone_number, dest_zone in local.spokes_zones[spoke_number] : {
        vpc           = spoke_vpc.id            # spoke routing table
        routing_table = spoke_vpc.routing_table # spoke routing table
        zone          = source_zone.zone        # transit zone
        name          = "egress-delegate-from-z${source_zone_number}-to-z${dest_zone_number}"
        destination   = dest_zone.cidr
        action        = "delegate"
        next_hop      = "0.0.0.0"
      }]
    ]
  ]]

  routes = local.settings.all_firewall ? flatten(concat(local.transit_egress, local.transit_egress_self_delegate, local.spoke_egress_to_cloud, local.spoke_egress_self_delegate)) : []
}

resource "ibm_is_vpc_routing_table_route" "spoke_transit" {
  for_each      = { for key, value in local.routes : key => value }
  vpc           = each.value.vpc
  routing_table = each.value.routing_table
  name          = each.value.name
  zone          = each.value.zone
  destination   = each.value.destination
  action        = each.value.action
  next_hop      = each.value.next_hop
}

output "routes" {
  value = ibm_is_vpc_routing_table_route.spoke_transit
  precondition {
    condition     = !local.settings.all_firewall || length(local.transit_ingress.routes) == 0
    error_message = <<-EOT
    The transit_ingress_tf layer has been configured to delegate ingress traffic.
    This is in conclict with routing all cross VPC traffic through the firewall-router.
    The config_tf/terraform.tfvars file has a configuration for all_firewall that must be set
    and the transit_ingress_tf layer must be applied again.
    EOT
  }
}
