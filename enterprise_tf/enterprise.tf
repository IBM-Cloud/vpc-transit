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
  settings         = data.terraform_remote_state.config.outputs.settings
}

module "enterprise" {
  source           = "../modules/vpc"
  name             = "${local.settings.basename}-enterprise"
  settings         = local.settings
  zones            = local.enterprise_zones
  make_route_table = false
}

output "vpc" {
  value = module.enterprise.vpc
}
