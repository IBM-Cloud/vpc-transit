# create firewall in the transit vpc.  Firewall is optional based on firewall variable.  Just a shim over the firewall module
variable "ibmcloud_api_key" {}

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}

locals {
  settings        = data.terraform_remote_state.config.outputs.settings
  provider_region = local.settings.region
}

module "firewall" {
  count  = local.settings.firewall ? 1 : 0
  source = "../modules/firewall_tf"
}

output "zones" {
  value = length(module.firewall) == 1 ? module.firewall[0].zones : {}
}
