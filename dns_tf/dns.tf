variable "ibmcloud_api_key" {}

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
  enterprise_zones  = data.terraform_remote_state.config.outputs.enterprise_zones
  transit_zones     = data.terraform_remote_state.config.outputs.transit_zones
  settings          = data.terraform_remote_state.config.outputs.settings
  tags              = local.settings.tags
  enterprise_vpc    = data.terraform_remote_state.enterprise.outputs.vpc
  transit_vpc       = data.terraform_remote_state.transit.outputs.vpc
  spokes            = data.terraform_remote_state.spokes.outputs
  test_instances_tf = data.terraform_remote_state.test_instances.outputs
  spokes_vpc        = local.spokes.vpcs
}

locals {
  dns_modules = merge(
    { enterprise = local.enterprise_vpc },
    { transit = local.transit_vpc },
    { for spoke_number, spoke_vpc in local.spokes_vpc : spoke_number => spoke_vpc }
  )
  instances = merge(
    { enterprise = local.test_instances_tf.enterprise.workers },
    { transit = local.test_instances_tf.transit.workers },
    { for spoke_number, spoke_output in local.test_instances_tf.spokes : spoke_number => spoke_output.workers }
  )
}

module "dns" {
  for_each          = local.dns_modules
  source            = "../modules/dns"
  name              = each.value.name
  resource_group_id = local.settings.resource_group_id
  vpc = {
    crn       = each.value.crn
    subnets   = [for zone in each.value.zones : zone.subnets[local.settings.subnet_dns]]
    instances = local.instances[each.key]
  }
  dns_zone_name = "${each.value.name}.com"
  tags          = local.tags
}

locals {
  dns_transit    = module.dns["transit"]
  dns_enterprise = module.dns["enterprise"]
  dns_spokes     = { for spoke_number, _ in local.spokes_vpc : spoke_number => module.dns[spoke_number] }
}

locals {
  module_spokes_keys = [for k, _ in local.dns_spokes : k]
  source_destination_match = flatten(concat(
    // transit -> enterprise for enterprise DNS names
    [{
      source      = local.dns_transit
      destination = local.dns_enterprise
      match       = local.dns_enterprise.dns.zone.name
    }],
    // enterprise -> transit for transit DNS names
    [{
      source      = local.dns_enterprise
      destination = local.dns_transit
      match       = local.dns_transit.dns.zone.name
    }],
    // enterprise -> transit for spoke DNS names
    [for k, s in local.dns_spokes : {
      source      = local.dns_enterprise
      destination = local.dns_transit
      match       = s.dns.zone.name
    }],
    // transit -> spoke for spoke DNS names
    [for k, s in local.dns_spokes : {
      source      = local.dns_transit
      destination = s
      match       = s.dns.zone.name
    }],
    [{
      source      = local.dns_enterprise
      destination = local.dns_transit
      match       = "appdomain.cloud"
    }],
    // spoke -> transit for enterprise DNS names
    [for k, s in local.dns_spokes : {
      source      = s
      destination = local.dns_transit
      match       = local.dns_enterprise.dns.zone.name
    }],
    // spoke -> transit for transit DNS names
    [for k, s in local.dns_spokes : {
      source      = s
      destination = local.dns_transit
      match       = local.dns_transit.dns.zone.name
    }],
    // spoke -> transit for spoke names, note this is nested
    [for k, s in local.dns_spokes : [
      for ki, si in local.dns_spokes : {
        source      = s
        destination = local.dns_transit
        match       = si.dns.zone.name
      }
      if k != ki
    ]],
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

output "module_dns" {
  value = module.dns
}
