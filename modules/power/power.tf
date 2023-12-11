variable "name" {}
variable "settings" {}
variable "zones_subnets" {
}
# zones is a list of both address_prefixes and subnets
variable "make_firewall_route_table" {}

locals {
  subnet            = var.zones_subnets[0][0]
  name              = var.name
  resource_group_id = var.settings.resource_group_id
  datacenter        = var.settings.datacenter
}

resource "ibm_resource_instance" "location" {
  name              = local.name
  resource_group_id = local.resource_group_id
  location          = local.datacenter
  service           = "power-iaas"
  plan              = "power-virtual-server-group"
}

resource "time_sleep" "wait_for_workspace_ready" {
  depends_on = [
    ibm_resource_instance.location
  ]
  create_duration = "1m"
}

resource "ibm_pi_network" "public" {
  depends_on = [
    time_sleep.wait_for_workspace_ready
  ]
  pi_network_name      = "${local.name}-public"
  pi_cloud_instance_id = ibm_resource_instance.location.guid
  pi_network_type      = "pub-vlan"
}

resource "ibm_pi_network" "private" {
  depends_on = [
    time_sleep.wait_for_workspace_ready
  ]
  pi_network_name      = "${local.name}-private"
  pi_cloud_instance_id = ibm_resource_instance.location.guid
  pi_network_type      = "vlan"
  pi_cidr              = local.subnet.cidr
  # TODO TODO todo
  pi_dns = ["10.1.0.68"]
}

output "power" {
  value = {
    guid = ibm_resource_instance.location.guid
    crn  = ibm_resource_instance.location.crn
    name = ibm_resource_instance.location.name
    network_private = {
      pi_network_name = ibm_pi_network.private.pi_network_name
      pi_network_type = ibm_pi_network.private.pi_network_type
      pi_cidr         = ibm_pi_network.private.pi_cidr
      pi_gateway      = ibm_pi_network.private.pi_gateway
      network_id      = ibm_pi_network.private.network_id
    }
    network_public = {
      pi_network_name = ibm_pi_network.public.pi_network_name
      pi_network_type = ibm_pi_network.public.pi_network_type
      pi_cidr         = ibm_pi_network.public.pi_cidr
      pi_gateway      = ibm_pi_network.public.pi_gateway
      network_id      = ibm_pi_network.public.network_id
    }
  }
}
