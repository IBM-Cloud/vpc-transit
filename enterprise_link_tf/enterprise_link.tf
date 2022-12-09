# linke enterprise to the transit vpc in the cloud

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

locals {
  provider_region = local.settings.region
  settings        = data.terraform_remote_state.config.outputs.settings
  enterprise_vpc  = data.terraform_remote_state.enterprise.outputs.vpc
  transit_vpc     = data.terraform_remote_state.transit.outputs.vpc
}

module "enterprise_link_tgw" {
  count          = local.settings.vpn ? 0 : 1
  source         = "../modules/enterprise_link_tgw"
  settings       = local.settings
  enterprise_vpc = local.enterprise_vpc
  transit_vpc    = local.transit_vpc
}

output "tg_gateway" {
  value = local.settings.vpn ? null : module.enterprise_link_tgw[0].tg_gateway
}
