# vpc_test_instances - add a test instance to the worker subnet in a vpc
variable "settings" {}
variable "power" {
  description = "power instance and network configuration"
}
variable "ssh_key_name" {}

resource "ibm_pi_image" "testacc_image" {
  pi_image_name        = "SLES15-SP4"
  pi_cloud_instance_id = var.power.guid
  pi_image_id          = "e00178e1-f763-41b7-adb0-b5da0edde4c9"
}

locals {
  user_data = file("${path.module}/user_data.sh")
}

output "user_data" {
  value = replace(local.user_data, "__NAME__", var.power.name)
}

resource "ibm_pi_instance" "worker" {
  pi_memory        = "4"
  pi_processors    = "2"
  pi_instance_name = var.power.name
  pi_proc_type     = "shared"
  pi_image_id      = ibm_pi_image.testacc_image.image_id
  # pi_key_pair_name     = ibm_pi_key.ssh_key_tmp.pi_key_name
  pi_key_pair_name     = var.ssh_key_name
  pi_sys_type          = "s922"
  pi_cloud_instance_id = var.power.guid
  pi_pin_policy        = "none"
  pi_storage_type      = "tier3"
  pi_network {
    // network_id = ibm_pi_network.private.network_id
    network_id = var.power.network_private.network_id
  }
  pi_network {
    //network_id = ibm_pi_network.power_networks.network_id
    network_id = var.power.network_public.network_id
  }
}
output "ibm_pi_instance_worker" {
  value = {
    pi_memory        = "4"
    pi_processors    = "2"
    pi_instance_name = var.power.name
    pi_proc_type     = "shared"
    pi_image_id      = ibm_pi_image.testacc_image.image_id
    # pi_key_pair_name     = ibm_pi_key.ssh_key_tmp.pi_key_name
    pi_key_pair_name     = var.ssh_key_name
    pi_sys_type          = "s922"
    pi_cloud_instance_id = var.power.guid
    pi_pin_policy        = "none"
    pi_storage_type      = "tier3"
    pi_network_private   = var.power.network_private.network_id
    pi_network_public    = var.power.network_public.network_id
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
    }
  }
}
