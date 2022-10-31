variable "ibmcloud_api_key" {}

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}

locals {
  provider_region  = local.settings.region
  enterprise_zones = data.terraform_remote_state.config.outputs.enterprise_zones
  transit_zones    = data.terraform_remote_state.config.outputs.transit_zones
  settings         = data.terraform_remote_state.config.outputs.settings
  tags             = local.settings.tags
}

module "transit" {
  source           = "../modules/vpc"
  name             = "${local.settings.basename}-transit"
  settings         = local.settings
  zones            = local.transit_zones
  make_route_table = true
}

output "vpc" {
  value = module.transit.vpc
}
