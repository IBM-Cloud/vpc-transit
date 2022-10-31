variable "name" {}
variable "tags" {}
variable "resource_group_id" {}
variable "plan" {}
variable "service" {}
variable "region" {}
variable "vpc" {}
variable "subnets" {}

locals {
  name = var.name
  tags = concat(var.tags, ["transit:${var.name}"])
}

resource "ibm_database" "database" {
  name              = local.name
  resource_group_id = var.resource_group_id
  plan              = var.plan
  service           = var.service
  location          = var.region
  service_endpoints = "private"
  tags              = local.tags
}

output "database" {
  value = ibm_database.database
  # todo
  # sensitive = true
}

resource "ibm_resource_key" "resource_key" {
  name                 = local.name
  resource_instance_id = ibm_database.database.id
  role                 = "Administrator"
  tags                 = local.tags
}

locals {
  resource_key = ibm_resource_key.resource_key
}

resource "time_sleep" "wait_for_database_initialization" {
  depends_on = [
    ibm_database.database
  ]
  create_duration = "5m"
}
resource "ibm_is_virtual_endpoint_gateway" "database" {
  depends_on = [
    time_sleep.wait_for_database_initialization
  ]
  vpc            = var.vpc.id
  name           = local.name
  resource_group = var.resource_group_id
  target {
    crn           = ibm_database.database.id
    resource_type = "provider_cloud_service"
  }

  # one Reserved IP for per zone in the VPC
  dynamic "ips" {
    for_each = { for subnet in var.subnets : subnet.id => subnet }
    content {
      subnet = ips.key
      name   = "${var.name}-${ips.value.name}"
    }
  }
  tags = local.tags
}

output "virtual_endpoint_gateway" {
  value = ibm_is_virtual_endpoint_gateway.database
}

output "database_key" {
  value = local.resource_key
  # todo
  # sensitive = true
}
