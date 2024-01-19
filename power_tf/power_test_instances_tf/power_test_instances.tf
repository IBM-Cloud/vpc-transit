# vpc_test_instances - add a test instance to the worker subnet in a vpc
variable "settings" {}
variable "power" {
  description = "power instance and network configuration"
}
variable "ssh_key_name" {}

data "ibm_pi_catalog_images" "my_images" {
  pi_cloud_instance_id = var.power.guid
}

data "ibm_pi_system_pools" "pools" {
  pi_cloud_instance_id = var.power.guid
}

locals {
  image_name      = "SLES15-SP5"
  user_data       = file("${path.module}/user_data.sh")
  matching_images = [for image in data.ibm_pi_catalog_images.my_images.images : image if image.name == local.image_name]
  image_id        = local.matching_images[0].image_id

  # grab first one on the list
  #sys_type        = "s1022"
  sys_type = data.ibm_pi_system_pools.pools.system_pools[0].type
}

resource "ibm_pi_image" "testacc_image" {
  pi_image_name        = local.image_name
  pi_cloud_instance_id = var.power.guid
  pi_image_id          = local.image_id
}

output "user_data" {
  value = replace(local.user_data, "__NAME__", var.power.name)
}

resource "ibm_pi_instance" "worker" {
  pi_memory            = "4"
  pi_processors        = "2"
  pi_instance_name     = var.power.name
  pi_proc_type         = "shared"
  pi_image_id          = ibm_pi_image.testacc_image.image_id
  pi_key_pair_name     = var.ssh_key_name
  pi_sys_type          = local.sys_type
  pi_cloud_instance_id = var.power.guid
  pi_pin_policy        = "none"
  pi_storage_type      = "tier3"
  pi_network {
    network_id = var.power.network_private.network_id
  }
  pi_network {
    network_id = var.power.network_public.network_id
  }
}

locals {
  networks = { for i, network in ibm_pi_instance.worker.pi_network : network.network_name => network }
}

output "workers" {
  value = {
    "${ibm_pi_instance.worker.pi_instance_name}" = {
      name                 = ibm_pi_instance.worker.pi_instance_name
      id                   = ibm_pi_instance.worker.id
      subnet_name          = var.power.network_private.pi_network_name
      fip                  = local.networks["${var.power.name}-public"].external_ip
      primary_ipv4_address = local.networks["${var.power.name}-private"].ip_address
      zone                 = "${var.settings.datacenter}-1"
    }
  }
}
