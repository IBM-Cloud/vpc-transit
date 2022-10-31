# VPE Virtual Private Endpoint Gateway resources in the spokes
variable "ibmcloud_api_key" {}

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "spokes" {
  backend = "local"

  config = {
    path = "../spokes_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "dns" {
  backend = "local"

  config = {
    path = "../dns_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "vpe_transit" {
  backend = "local"

  config = {
    path = "../vpe_transit_tf/terraform.tfstate"
  }
}

locals {
  provider_region = local.settings.region
  tags            = local.settings.tags
  spokes          = data.terraform_remote_state.spokes.outputs
  settings        = data.terraform_remote_state.config.outputs.settings
  dns             = data.terraform_remote_state.dns.outputs
  vpe_transit     = data.terraform_remote_state.vpe_transit.outputs
  spokes_vpc      = local.spokes.vpcs
}

module "vpe_resources" {
  for_each          = { for spoke_number, vpc in local.spokes_vpc : spoke_number => vpc }
  source            = "../modules/vpe_resources"
  make_redis        = local.settings.make_redis
  make_postgresql   = local.settings.make_postgresql
  make_cos          = local.settings.make_cos
  basename          = each.value.name
  tags              = local.tags
  resource_group_id = local.settings.resource_group_id
  region            = local.settings.region
  vpc               = each.value
  subnets           = [for zone in each.value.zones : zone.subnets[local.settings.subnet_vpe]]
}

locals {
  dns_transit    = local.dns.module_dns["transit"]
  dns_enterprise = local.dns.module_dns["enterprise"]
  dns_spokes     = { for spoke_number, _ in local.spokes_vpc : spoke_number => local.dns.module_dns[spoke_number] }
  spoke_hostname = flatten([for spoke, vpe_resource in module.vpe_resources : [for resource in vpe_resource.resources : {
    spoke    = spoke
    hostname = resource.hostname
    }
    if resource.type != "cos"
  ]])
  source_destination_match = flatten(concat(
    // spoke -> transit for VPE fully qualified names in transit
    [for spoke_number, dns_spoke in local.dns_spokes :
      [for resource in local.vpe_transit.resources : {
        source      = dns_spoke
        destination = local.dns_transit
        match       = resource.hostname
        } if resource.type != "cos"
    ]],
    // transit -> spoke for VPE fully qualified names
    [for sk, vpe in zipmap(range(length(local.spoke_hostname)), local.spoke_hostname) : {
      source      = local.dns_transit
      destination = local.dns_spokes[vpe.spoke]
      match       = vpe.hostname
    }],
    // spoke -> other spokes for VPE fully qualified names
    [for spoke_number, dns_spoke in local.dns_spokes :
      [for sk, vpe in zipmap(range(length(local.spoke_hostname)), local.spoke_hostname) : {
        source      = dns_spoke
        destination = local.dns_spokes[vpe.spoke]
        match       = vpe.hostname
      } if vpe.spoke != spoke_number]
    ],
  ))
  source_destination_match_map = zipmap(range(length(local.source_destination_match)), local.source_destination_match)
}

resource "ibm_dns_custom_resolver_forwarding_rule" "spokes" {
  for_each    = local.source_destination_match_map
  instance_id = each.value.source.dns.resource_instance.guid
  resolver_id = split(":", each.value.source.dns.custom_resolver.id)[0]
  type        = "zone"
  match       = each.value.match
  forward_to  = [for location in each.value.destination.dns.custom_resolver.locations : location.dns_server_ip]
}

output "resources" {
  # todo
  sensitive = true
  value     = { for key, value in module.vpe_resources : key => value.resources }
}
