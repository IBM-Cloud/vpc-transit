/*
dns zone will create the following resources 
- dns zone with name dns_zone_name
- adds the vpc as a permitted network to the dns zone
- an A record in the dns zone for each worker instance with the same name as the instance: instance.dns_zone_name

The vpc variable is in the format created by the vpc module
*/
variable "dns_resource_guid" {}
variable "vpc_crn" {}
variable "dns_zone_name" {}
variable "a_records" {
  type = list(object({
    name = string
    ip   = string
  }))
  description = "list of name, ip pairs like [{name=aaa-spoke0-z1-worker, ip=10.1.0.4}]"
}

resource "ibm_dns_zone" "location" {
  name        = var.dns_zone_name
  instance_id = var.dns_resource_guid
}

resource "ibm_dns_permitted_network" "location" {
  instance_id = ibm_dns_zone.location.instance_id
  zone_id     = ibm_dns_zone.location.zone_id
  vpc_crn     = var.vpc_crn
  type        = "vpc"
}

resource "ibm_dns_resource_record" "server" {
  for_each    = { for index, a_record in var.a_records : index => a_record }
  instance_id = ibm_dns_zone.location.instance_id
  zone_id     = ibm_dns_zone.location.zone_id
  type        = "A"
  name        = each.value.name
  rdata       = each.value.ip
  ttl         = 3600
}

# list of records
output "a_records" {
  value = [for index, a_record in ibm_dns_resource_record.server : {
    name     = var.a_records[tonumber(index)].name
    ip       = a_record.rdata
    dns_name = "${var.a_records[tonumber(index)].name}.${var.dns_zone_name}"
    # this works on the second terraform apply but not on the first
    #dns_name = a_record.name
  }]
}
