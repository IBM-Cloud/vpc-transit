variable "ibmcloud_api_key" {}

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
data "terraform_remote_state" "spokes" {
  backend = "local"

  config = {
    path = "../spokes_tf/terraform.tfstate"
  }
}

locals {
  provider_region = local.settings.region
  config          = data.terraform_remote_state.config.outputs
  enterprise      = data.terraform_remote_state.enterprise.outputs
  transit         = data.terraform_remote_state.transit.outputs
  spokes          = data.terraform_remote_state.spokes.outputs
  settings        = local.config.settings
}

module "enterprise" {
  source   = "./vpc_test_instances_tf"
  settings = local.settings
  vpc      = local.enterprise.vpc
}

output "enterprise" {
  value = module.enterprise
}

module "transit" {
  source   = "./vpc_test_instances_tf"
  settings = local.settings
  vpc      = local.transit.vpc
}

output "transit" {
  value = module.transit
}

module "spokes" {
  for_each = { for spoke_number, vpc in local.spokes.vpcs : spoke_number => vpc }
  source   = "./vpc_test_instances_tf"
  settings = local.settings
  vpc      = each.value
}

output "spokes" {
  value = module.spokes
}

/*
module "transit" {
  source            = "./vpc_test_instances_tf"
  name              = "${local.settings.basename}-transit"
  settings          = local.settings
  tags              = local.tags
  resource_group_id = local.settings.resource_group_id
  make_route_table  = true
  #make_route_table = false
  zones = local.transit_zones
  myip  = local.settings.myip
  # todo look at the security groups more closely
  security_group_inbound_cidrs = [local.settings.cloud_cidr, local.settings.enterprise_cidr]
  ssh_key_ids                  = [local.settings.ssh_key.id]
  image_id                     = local.settings.image_id
  profile                      = local.settings.profile
}

module "spokes" {
  for_each                     = { for spoke, zones in local.spokes_zones : spoke => zones }
  source                       = "./vpc_test_instances_tf"
  name                         = "${local.settings.basename}-spoke${each.key}"
  settings                     = local.settings
  tags                         = local.tags
  resource_group_id            = local.settings.resource_group_id
  make_route_table             = false
  zones                        = each.value
  myip                         = local.settings.myip
  security_group_inbound_cidrs = [local.settings.enterprise_cidr, local.settings.cloud_cidr]
  ssh_key_ids                  = [local.settings.ssh_key.id]
  image_id                     = local.settings.image_id
  profile                      = local.settings.profile
}

output "vpcs" {
  value = [for spoke in module.spokes : spoke.vpc]
}


output "vpc" {
  value = module.transit.vpc
}

output "vpc" {
  value = {
    zones = [for zone in local.zones : {
      subnets = [for subnet in zone.subnets : {
        # todo remove?  used by tests
        instances = { for key, value in ibm_is_instance.workers : key => {
          id                   = value.id
          name                 = value.name
          fip                  = ibm_is_floating_ip.location[key].address
          ssh                  = "ssh root@${ibm_is_floating_ip.location[key].address}"
          primary_ipv4_address = value.primary_network_interface[0].primary_ipv4_address
          zone                 = value.zone
    } } }] }]
  }
}

*/
