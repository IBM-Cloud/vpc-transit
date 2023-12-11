# test load balancers in the spokes

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

locals {
  provider_region = local.settings.region
  config          = data.terraform_remote_state.config.outputs
  enterprise      = data.terraform_remote_state.enterprise.outputs
  transit         = data.terraform_remote_state.transit.outputs
  spokes          = data.terraform_remote_state.spokes.outputs
  settings        = local.config.settings
  lb_types = flatten([{
    lb_type     = "alb-regional"
    zone_number = -1
    }, [for lb_type in ["alb-zonal", "nlb-zonal"] : [
      for zone_number, _ in local.transit.vpc.zones : {
        lb_type     = lb_type
        zone_number = zone_number
      }
    ]]
  ])

  # the commented out bits show how to make load balancers in the transit
  # only in spoke 0, if it exists
  # spoke_count = length(local.spokes.vpcs)
  spoke_count = min(1, length(local.spokes.vpcs))
  lbs = flatten([for lb_type in local.lb_types : [
    /*
    {
    name        = "transit-${lb_type.lb_type}-z${lb_type.zone_number}"
    vpc         = local.transit.vpc
    lb_type     = lb_type.lb_type
    zone_number = lb_type.zone_number
    },
  */
    [for lb_type in local.lb_types : [for spoke_number in range(local.spoke_count) : {
      name        = "spoke${spoke_number}-${lb_type.lb_type}-z${lb_type.zone_number}"
      vpc         = local.spokes.vpcs[spoke_number]
      lb_type     = lb_type.lb_type
      zone_number = lb_type.zone_number
    }]]
  ]])

  zlbs = { for lb in local.lbs : lb.name => lb if local.settings.test_lbs }
}


# All load balancers created are put into a single map and created here.  Transit and all spokes:
module "lbs" {
  for_each    = local.zlbs
  source      = "./test_lb_tf"
  settings    = local.settings
  vpc         = each.value.vpc
  name        = each.value.name
  lb_type     = each.value.lb_type
  zone_number = each.value.zone_number
}

output "lbs" {
  value = module.lbs
}
