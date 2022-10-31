# transit gateway between tranit and spokes

variable "ibmcloud_api_key" {}

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
data "terraform_remote_state" "spokes" {
  backend = "local"

  config = {
    path = "../spokes_tf/terraform.tfstate"
  }
}

locals {
  provider_region = local.settings.region
  settings        = data.terraform_remote_state.config.outputs.settings
  spokes          = data.terraform_remote_state.spokes.outputs
  transit_vpc     = data.terraform_remote_state.transit.outputs.vpc
  spokes_vpc      = local.spokes.vpcs
  tags            = local.settings.tags
}

resource "ibm_tg_gateway" "tgw" {
  name           = "${local.settings.basename}-tgw"
  location       = local.settings.region
  global         = false
  resource_group = local.settings.resource_group_id
  tags           = local.settings.tags
}

resource "ibm_tg_connection" "spokes" {
  for_each     = { for spoke_number, vpc in local.spokes_vpc : spoke_number => vpc }
  network_type = "vpc"
  gateway      = ibm_tg_gateway.tgw.id
  name         = each.value.name
  network_id   = each.value.crn
}

resource "ibm_tg_connection" "transit" {
  network_type = "vpc"
  gateway      = ibm_tg_gateway.tgw.id
  name         = local.transit_vpc.name
  network_id   = local.transit_vpc.crn
}

output "tg_gateway" {
  value = {
    id = ibm_tg_gateway.tgw.id
    spoke_connections = { for key, value in ibm_tg_connection.spokes : key => {
      name          = value.name
      connection_id = value.connection_id
    } }
    transit_connection = {
      name          = ibm_tg_connection.transit.name
      connection_id = ibm_tg_connection.transit.connection_id
    }
  }
}
