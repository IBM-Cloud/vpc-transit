# VPE Virtual Private Endpoint Gateway resources in the transit

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
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
  tags            = local.settings.tags
  transit_vpc     = data.terraform_remote_state.transit.outputs.vpc
  settings        = data.terraform_remote_state.config.outputs.settings
}

module "vpe_resources" {
  source            = "../modules/vpe_resources"
  make_redis        = local.settings.make_redis
  make_postgresql   = local.settings.make_postgresql
  make_cos          = local.settings.make_cos
  basename          = "${local.settings.basename}-transit"
  tags              = local.tags
  resource_group_id = local.settings.resource_group_id
  region            = local.settings.region
  vpc               = local.transit_vpc
  subnets           = [for zone in local.transit_vpc.zones : zone.subnets[local.settings.subnet_vpe]]
}

output "resources" {
  # todo
  sensitive = true
  value     = module.vpe_resources.resources
}
