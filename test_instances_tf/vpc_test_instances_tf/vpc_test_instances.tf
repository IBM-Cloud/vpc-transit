# vpc_test_instances - add a test instance to the worker subnet in a vpc
variable "settings" {}
variable "vpc" {}
variable "profile" {}

locals {
  tags                         = var.settings.tags
  resource_group_id            = var.settings.resource_group_id
  security_group_inbound_cidrs = [var.settings.cloud_cidr, var.settings.enterprise_cidr]
  ssh_key_ids                  = var.settings.ssh_key_ids
  image_id                     = var.settings.image_id
  profile                      = var.settings.profile

  user_data      = file("${path.module}/user_data.sh")
  worker_subnets = [for _, zone in var.vpc.zones : zone.subnets[var.settings.subnet_worker]]
}

# instance in each worker subnet
resource "ibm_is_instance" "workers" {
  for_each       = { for subnet in local.worker_subnets : subnet.name => subnet }
  name           = each.value.name
  vpc            = var.vpc.id
  zone           = each.value.zone
  keys           = local.ssh_key_ids
  image          = local.image_id
  profile        = local.profile
  resource_group = local.resource_group_id
  primary_network_interface {
    subnet = each.value.id
  }
  user_data = replace(local.user_data, "__NAME__", each.value.name)
  tags      = local.tags
}

resource "ibm_is_floating_ip" "workers" {
  for_each       = ibm_is_instance.workers
  name           = each.value.name
  target         = each.value.primary_network_interface[0].id
  resource_group = local.resource_group_id
  tags           = local.tags
}


output "workers" {
  value = {
    for worker_name, worker in ibm_is_instance.workers : worker_name => {
      id                   = worker.id
      name                 = worker.name
      subnet_name          = worker.name
      fip                  = ibm_is_floating_ip.workers[worker_name].address
      primary_ipv4_address = worker.primary_network_interface[0].primary_ipv4_address
      zone                 = worker.zone
    }
  }
}
