# dns instance configuration

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
data "terraform_remote_state" "test_instances" {
  backend = "local"

  config = {
    path = "../test_instances_tf/terraform.tfstate"
  }
}

locals {
  provider_region   = local.settings.region
  settings          = data.terraform_remote_state.config.outputs.settings
  tags              = local.settings.tags
  enterprise_vpc    = data.terraform_remote_state.enterprise.outputs.vpc
  transit_vpc       = data.terraform_remote_state.transit.outputs.vpc
  test_instances_tf = data.terraform_remote_state.test_instances.outputs
  spokes_tf         = data.terraform_remote_state.spokes.outputs
  spoke_vpcs        = local.spokes_tf.vpcs

  enterprise_dns_resource = module.enterprise_dns_resource.dns_resource
  transit_dns_resource    = module.transit_dns_resource.dns_resource

  # TODO transit_dns_resource    = data.terraform_remote_state.transit.outputs.dns_resource
}

module "enterprise_dns_resource" {
  source            = "../modules/dns_resource"
  name              = "${local.settings.basename}-enterprise"
  resource_group_id = local.settings.resource_group_id
  vpc = {
    crn     = local.enterprise_vpc.crn
    subnets = [for zone in local.enterprise_vpc.zones : zone.subnets[local.settings.subnet_dns]]
  }
  tags = local.tags
}

module "transit_dns_resource" {
  source            = "../modules/dns_resource"
  name              = "${local.settings.basename}-transit"
  resource_group_id = local.settings.resource_group_id
  vpc = {
    crn     = local.transit_vpc.crn
    subnets = [for zone in local.transit_vpc.zones : zone.subnets[local.settings.subnet_dns]]
  }
  tags = local.tags
}

output "transit_dns_resource" {
  value = module.transit_dns_resource.dns_resource
}

# create zone in enterprise DNS and populate with enterprise A records
module "enterprise_zone" {
  source            = "../modules/dns_zone"
  dns_resource_guid = local.enterprise_dns_resource.resource_instance.guid
  vpc_crn           = local.enterprise_vpc.crn
  dns_zone_name     = local.settings.subdomain_enterprise
  a_records = [for index, instance in local.test_instances_tf.enterprise.workers : {
    name = instance.name
    ip   = instance.primary_ipv4_address
  }]
}

locals {
  transit_and_spoke_a_records = flatten(concat([for index, instance in local.test_instances_tf.transit.workers : {
    name = instance.name
    ip   = instance.primary_ipv4_address
    }], [for spoke_number, spoke_output in local.test_instances_tf.spokes : [for index, instance in spoke_output.workers : {
      name = instance.name
      ip   = instance.primary_ipv4_address
  }]]))
}

# create zone in transit DNS and populate with both transit and spoke A records 
module "transit" {
  source            = "../modules/dns_zone"
  dns_resource_guid = local.transit_dns_resource.resource_instance.guid
  vpc_crn           = local.transit_vpc.crn
  dns_zone_name     = local.settings.subdomain_cloud
  a_records         = local.transit_and_spoke_a_records
}

output "a_records" {
  value = concat(module.enterprise_zone.a_records, module.transit.a_records)
}

locals {
  source_destination_match = flatten(concat(
    // enterprise -> transit for all servers in the cloud, transit or spokes, x.cloud.example.com
    [{
      source_dns_resource      = local.enterprise_dns_resource
      destination_dns_resource = local.transit_dns_resource
      match                    = local.settings.subdomain_cloud
    }],
    // transit -> enterprise for all enterprise servers, x.enterprise.example.com
    [{
      source_dns_resource      = local.transit_dns_resource
      destination_dns_resource = local.enterprise_dns_resource
      match                    = local.settings.subdomain_enterprise
    }],
    // enterprise -> transit for all IBM services via VPEs, these will be resolved by the transit shared hub
    [for domain in ["cloud.ibm.com", "appdomain.cloud", "networklayer.com", "isv.com", "isops.ibm.com", "icr.io"] : {
      source_dns_resource      = local.enterprise_dns_resource
      destination_dns_resource = local.transit_dns_resource
      match                    = domain
    }],
  ))
  source_destination_match_map = zipmap(range(length(local.source_destination_match)), local.source_destination_match)
}

resource "ibm_dns_custom_resolver_forwarding_rule" "spokes" {
  for_each    = local.source_destination_match_map
  instance_id = each.value.source_dns_resource.resource_instance.guid
  resolver_id = split(":", each.value.source_dns_resource.custom_resolver.id)[0]
  type        = "zone"
  match       = each.value.match
  forward_to  = [for location in each.value.destination_dns_resource.custom_resolver.locations : location.dns_server_ip]
}

# allow each spoke -> transit DNS bind to succeed
resource "ibm_iam_authorization_policy" "policy" {
  for_each = { for index, vpc in local.spoke_vpcs : index => vpc }
  #"DNSBindingConnector",
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
  subject_attributes {
    name  = "resource"
    value = each.value.id
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

# spokes switch from using their own DNS to start using the hub DNS resolvers
resource "ibm_is_vpc_dns_resolution_binding" "spoke_vpc_dns_resolution_binding_by_id" {
  for_each   = { for index, vpc in local.spoke_vpcs : index => vpc }
  depends_on = [module.transit_dns_resource, ibm_iam_authorization_policy.policy]
  name       = each.value.name
  vpc_id     = each.value.id
  vpc {
    id = local.transit_vpc.id
  }
}

data "ibm_iam_auth_token" "tokendata" {}

locals {
  api_version      = "2024-04-04"
  vpc_api_endpoint = "https://${local.settings.region}.iaas.cloud.ibm.com"
  patch_delegated = {
    dns = {
      resolver = {
        type = "delegated"
        vpc = {
          id = local.transit_vpc.id
        }
        dns_binding_name = "spoke-to-transit"
      }
    }
  }
  patch_system = {
    dns = {
      resolver = {
        type = "system"
        vpc  = null
      }
    }
  }
  iam_access_token = sensitive(data.ibm_iam_auth_token.tokendata.iam_access_token)
  headers = {
    "Content-Type"  = "application/json"
    "Authorization" = local.iam_access_token
  }
}

# turn on delegated in the spokes to allow DNS requests to delegate to the transit VPC DNS resolver
resource "terracurl_request" "patch_delegated" {
  depends_on   = [ibm_is_vpc_dns_resolution_binding.spoke_vpc_dns_resolution_binding_by_id]
  for_each     = { for index, vpc in local.spoke_vpcs : index => vpc }
  name         = each.value.name
  url          = "${local.vpc_api_endpoint}/v1/vpcs/${each.value.id}?version=${local.api_version}&generation=2"
  method       = "PATCH"
  request_body = jsonencode(local.patch_delegated)
  headers      = local.headers
  response_codes = [
    200,
    204
  ]

  destroy_url          = "${local.vpc_api_endpoint}/v1/vpcs/${each.value.id}?version=${local.api_version}&generation=2"
  destroy_method       = "PATCH"
  destroy_request_body = jsonencode(local.patch_system)
  destroy_headers      = local.headers
  destroy_response_codes = [
    200,
    204
  ]
}
