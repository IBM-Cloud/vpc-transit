# spokes - vpc for each spoke

variable "ibmcloud_api_key" {}

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}

locals {
  provider_region = local.settings.region
  settings        = data.terraform_remote_state.config.outputs.settings
  spokes_zones    = data.terraform_remote_state.config.outputs.spokes_zones
  tags            = local.settings.tags
}

module "spokes" {
  for_each         = { for spoke, zones in local.spokes_zones : spoke => zones }
  source           = "../modules/vpc"
  name             = "${local.settings.basename}-spoke${each.key}"
  settings         = local.settings
  zones            = each.value
  make_route_table = false
}

output "vpcs" {
  value = [for spoke in module.spokes : spoke.vpc]
}
