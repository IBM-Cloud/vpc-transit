variable "settings" {}
variable "enterprise_vpc" {}
variable "transit_vpc" {}

locals {
  settings       = var.settings
  transit_vpc    = var.transit_vpc
  enterprise_vpc = var.enterprise_vpc
}

resource "ibm_tg_gateway" "tgw" {
  name           = "${local.settings.basename}-tgw-link"
  location       = local.settings.region
  global         = false
  resource_group = local.settings.resource_group_id
  tags           = local.settings.tags
}

resource "ibm_tg_connection" "enterprise_link" {
  for_each = {
    enterprise = local.enterprise_vpc
    transit    = local.transit_vpc
  }
  network_type = "vpc"
  gateway      = ibm_tg_gateway.tgw.id
  name         = each.value.name
  network_id   = each.value.crn
}

output "tg_gateway" {
  value = ibm_tg_gateway.tgw
}
output "tg_connections" {
  value = ibm_tg_connection.enterprise_link
}
