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
data "terraform_remote_state" "vpe_spokes" {
  backend = "local"

  config = {
    path = "../vpe_spokes_tf/terraform.tfstate"
  }
}

locals {
  config_tf      = data.terraform_remote_state.config.outputs
  spokes_tf      = data.terraform_remote_state.spokes.outputs
  dns_tf         = data.terraform_remote_state.dns.outputs
  vpe_transit_tf = data.terraform_remote_state.vpe_transit.outputs
  vpe_spokes_tf  = data.terraform_remote_state.vpe_spokes.outputs

  settings        = local.config_tf.settings
  provider_region = local.settings.region
  tags            = local.settings.tags
  spokes_vpc      = local.spokes_tf.vpcs

}

locals {
  dns_transit    = local.dns_tf.module_dns["transit"]
  dns_enterprise = local.dns_tf.module_dns["enterprise"]
  dns_spokes     = { for spoke_number, _ in local.spokes_vpc : spoke_number => local.dns_tf.module_dns[spoke_number] }
  spoke_hostname = flatten([for spoke, vpe_resource in local.vpe_spokes_tf.resources : [for resource in vpe_resource.resources : {
    spoke    = spoke
    hostname = resource.hostname
    }
    if resource.type != "cos"
  ]])
  source_destination_match = flatten(concat(
    // spoke -> transit for VPE fully qualified names in transit
    [for spoke_number, dns_spoke in local.dns_spokes :
      [for resource in local.vpe_transit_tf.resources : {
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

  ibm_dns_custom_resolver_forwarding_rule = { for each_key, each_value in local.source_destination_match_map : each_key => {
    instance_id = each_value.source.dns.resource_instance.guid
    resolver_id = split(":", each_value.source.dns.custom_resolver.id)[0]
    type        = "zone"
    match       = each_value.match
    forward_to  = [for location in each_value.destination.dns.custom_resolver.locations : location.dns_server_ip]
  } }
}

output "ibm_dns_custom_resolver_forwarding_rule" {
  sensitive = true
  value     = local.ibm_dns_custom_resolver_forwarding_rule
}

resource "ibm_dns_custom_resolver_forwarding_rule" "spokes" {
  for_each    = local.ibm_dns_custom_resolver_forwarding_rule
  instance_id = each.value.instance_id
  resolver_id = each.value.resolver_id
  type        = "zone"
  match       = each.value.match
  forward_to  = each.value.forward_to
}
