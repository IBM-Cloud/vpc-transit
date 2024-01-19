variable "name" {}
variable "settings" {}
variable "private_subnet" {}
variable "dns_ips" {}

locals {
  private_subnet    = var.private_subnet
  name              = var.name
  resource_group_id = var.settings.resource_group_id
  datacenter        = var.settings.datacenter
  pi_network_mtu    = 1450
  crn               = ibm_resource_instance.location.crn
  workspace_id      = ibm_resource_instance.location.guid
  # crn             = ibm_pi_workspace.location.crn not supported yet
  # workspace_id    = ibm_pi_workspace.location.id
}

/*
resource "ibm_pi_workspace" "location" {
  pi_name              = local.name
  pi_datacenter        = local.datacenter
  pi_resource_group_id = local.resource_group_id
  # pi_plan              = "power-virtual-server-group"
  pi_plan = "public"
}
*/

resource "ibm_resource_instance" "location" {
  name              = local.name
  resource_group_id = local.resource_group_id
  location          = local.datacenter
  service           = "power-iaas"
  plan              = "power-virtual-server-group"
}

resource "time_sleep" "wait_for_workspace_ready" {
  depends_on = [
    local.workspace_id
  ]
  create_duration = "1m"
}

resource "ibm_pi_network" "public" {
  depends_on = [
    time_sleep.wait_for_workspace_ready
  ]
  pi_network_name      = "${local.name}-public"
  pi_cloud_instance_id = local.workspace_id
  pi_network_type      = "pub-vlan"
  pi_network_mtu       = local.pi_network_mtu
}

resource "ibm_pi_network" "private" {
  depends_on = [
    time_sleep.wait_for_workspace_ready
  ]
  pi_network_name      = "${local.name}-private"
  pi_cloud_instance_id = local.workspace_id
  pi_network_type      = "vlan"
  pi_cidr              = local.private_subnet.cidr
  pi_dns               = [var.dns_ips[0]]
  pi_network_mtu       = local.pi_network_mtu
  # pi_dns               = var.dns_ips
}

output "power" {
  value = {
    guid = local.workspace_id
    name = local.name
    crn  = local.crn
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
