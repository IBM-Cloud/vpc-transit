/*
dns module will create the following resources 
- dns service
- dns zone with name dns_zone_name
- adds the vpc as a permitted network to the dns zone
- an A record in the dns zone for each worker instance with the same name as the instance: instance.dns_zone_name
- add a dns custom resolver in the vpc dns subnets

The vpc variable is in the format created by the vpc module
*/
variable "name" {}
variable "resource_group_id" {}
variable "vpc" {}
variable "dns_zone_name" {}
variable "tags" {}

locals {
  zone_name = var.dns_zone_name
}
resource "ibm_resource_instance" "dns" {
  name              = var.name
  resource_group_id = var.resource_group_id
  location          = "global"
  service           = "dns-svcs"
  plan              = "standard-dns"
  tags              = var.tags
}

resource "ibm_dns_zone" "location" {
  name        = local.zone_name
  instance_id = ibm_resource_instance.dns.guid
}

resource "ibm_dns_permitted_network" "location" {
  instance_id = ibm_dns_zone.location.instance_id
  zone_id     = ibm_dns_zone.location.zone_id
  vpc_crn     = var.vpc.crn
  type        = "vpc"
}

resource "ibm_dns_resource_record" "server" {
  for_each    = var.vpc.instances
  instance_id = ibm_dns_zone.location.instance_id
  zone_id     = ibm_dns_zone.location.zone_id
  type        = "A"
  name        = each.value.name
  rdata       = each.value.primary_ipv4_address
  ttl         = 3600
}

# The resolver is attached to 3 subnets.  But there may only be 1 or 2 subnets provided
locals {
  subnets = slice(concat(var.vpc.subnets, var.vpc.subnets, var.vpc.subnets), 0, 3)
}
resource "ibm_dns_custom_resolver" "location" {
  name        = var.name
  instance_id = ibm_resource_instance.dns.guid
  description = "enterprise to transit and transit to enterprise"
  dynamic "locations" {
    for_each = local.subnets
    content {
      subnet_crn = locations.value.crn
      enabled    = true
    }
  }
}

output "dns" {
  value = {
    resource_instance = {
      guid = ibm_resource_instance.dns.guid
    }
    zone = {
      zone_id = ibm_dns_zone.location.zone_id
      name    = ibm_dns_zone.location.name
    }
    resource_records = { for key, value in ibm_dns_resource_record.server : key => {
      type  = value.type
      name  = value.name
      rdata = value.rdata
    } }
    custom_resolver = {
      id        = ibm_dns_custom_resolver.location.id
      locations = ibm_dns_custom_resolver.location.locations
    }
  }
}
