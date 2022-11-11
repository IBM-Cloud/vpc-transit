# VPE Virtual Private Endpoint Gateway resources in the spokes
variable "ibmcloud_api_key" {}

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
data "terraform_remote_state" "dns" {
  backend = "local"

  config = {
    path = "../dns_tf/terraform.tfstate"
  }
}
locals {
  spokes_tf       = data.terraform_remote_state.spokes.outputs
  config_tf       = data.terraform_remote_state.config.outputs
  settings        = local.config_tf.settings
  provider_region = local.settings.region
  tags            = local.settings.tags
  spokes_vpc      = local.spokes_tf.vpcs
}

module "vpe_resources" {
  for_each          = { for spoke_number, vpc in local.spokes_vpc : spoke_number => vpc }
  source            = "../modules/vpe_resources"
  make_redis        = local.settings.make_redis
  make_postgresql   = local.settings.make_postgresql
  make_cos          = local.settings.make_cos
  basename          = each.value.name
  tags              = local.tags
  resource_group_id = local.settings.resource_group_id
  region            = local.settings.region
  vpc               = each.value
  subnets           = [for zone in each.value.zones : zone.subnets[local.settings.subnet_vpe]]
}

output "resources" {
  sensitive = true
  value     = module.vpe_resources
}
