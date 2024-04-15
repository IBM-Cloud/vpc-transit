# transit VPC

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}

locals {
  config_tf        = data.terraform_remote_state.config.outputs
  settings         = local.config_tf.settings
  provider_region  = local.settings.region
  transit_zones    = local.config_tf.transit_zones
  cloud_zones_cidr = local.settings.cloud_zones_cidr
  tags             = local.settings.tags
  name             = "${local.settings.basename}-transit"

  zones_subnets = [for zone_number, zone in local.transit_zones : [for subnet_number, subnet in zone.subnets : {
    subnet_number = subnet_number # subnet in zone: 0,1,2,3
    zone          = subnet.zone   # us-south-1
    cidr          = subnet.cidr
    name          = subnet.name
  }]]
}

module "transit" {
  source                    = "../modules/vpc"
  name                      = local.name
  settings                  = local.settings
  zones_address_prefixes    = [for zone_number, zone_cidr in local.transit_zones : [zone_cidr]]
  zones_subnets             = local.zones_subnets
  make_firewall_route_table = true
  hub_vpc_id                = null
  is_hub                    = true
}

output "vpc" {
  value = module.transit.vpc
}

locals {
  transit_vpc = module.transit.vpc
}

# dns for transit hub must be created before the spoke vpcs.  The spoke vpcs must delegate to the hub during spoke vpc creation.
module "transit_dns_resource" {
  source            = "../modules/dns_resource"
  name              = local.name
  resource_group_id = local.settings.resource_group_id
  vpc = {
    crn     = local.transit_vpc.crn
    subnets = [for zone in local.transit_vpc.zones : zone.subnets[local.settings.subnet_dns]]
  }
  tags = local.tags
}

# allow all future spoke -> transit DNS bind to succeed
resource "ibm_iam_authorization_policy" "policy" {
  roles = [
    "DNS Binding Connector",
  ]
  subject_attributes {
    name  = "accountId"
    value = local.settings.account_id
  }
  subject_attributes {
    name  = "serviceName"
    value = "is"
  }
  subject_attributes {
    name  = "resourceType"
    value = "vpc"
  }
  resource_attributes {
    name  = "accountId"
    value = local.settings.account_id
  }
  resource_attributes {
    name  = "serviceName"
    value = "is"
  }
  resource_attributes {
    name  = "vpcId"
    value = local.transit_vpc.id
  }
}

output "dns_resource" {
  value = module.transit_dns_resource.dns_resource
}
