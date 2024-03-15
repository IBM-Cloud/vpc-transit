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
  profile  = local.settings.profile
}

output "enterprise" {
  value = module.enterprise
}

module "transit" {
  source   = "./vpc_test_instances_tf"
  settings = local.settings
  vpc      = local.transit.vpc
  profile  = local.settings.profile
}

output "transit" {
  value = module.transit
}

module "spokes" {
  for_each = { for spoke_number, vpc in local.spokes.vpcs : spoke_number => vpc }
  source   = "./vpc_test_instances_tf"
  settings = local.settings
  vpc      = each.value
  profile  = local.settings.spoke_profile
}

output "spokes" {
  value = module.spokes
}
