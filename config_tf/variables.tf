variable "ssh_key_name" {
  default = ""
}
variable "resource_group_name" {}
variable "basename" {}
variable "region" {}
variable "datacenter" {
  type = string
}
variable "spoke_count_vpc" {
  type = number
}
variable "spoke_count_power" {
  type    = number
  default = 0
}
variable "make_redis" {
  type    = bool
  default = false
}
variable "make_postgresql" {
  type    = bool
  default = false
}
variable "make_cos" {
  type    = bool
  default = false
}

# enterprise link is vpn or tgw
variable "vpn" {
  type    = bool
  default = false
}

# route based vpn does not work with both: enterprise -> vpe and enterprise -> spoke
variable "vpn_route_based" {
  default = false
}

# number of zones for each vpn location (enterprise and transit)
variable "zones" {}

variable "profile" {
  default = "cx2-2x4"
}
# firewall implementation
# is there a firewall
variable "firewall" {
  type    = bool
  default = true
}
# is there a network load balancer for the firewall?
variable "firewall_nlb" {
  type = bool
}
variable "number_of_firewalls_per_zone" {
  type = number
}

# spoke <-> spoke and transit <-> spoke traffic should also flow through the firewall
variable "all_firewall" {
  type = bool
}

# test load balancers
variable "test_lbs" {
  type    = bool
  default = false
}

resource "null_resource" "preconditions" {
  lifecycle {
    precondition {
      condition     = !(var.spoke_count_power > 0 && var.datacenter == "")
      error_message = "datacenter is required when using powerVS spokes"
    }
    precondition {
      condition     = !(var.spoke_count_power == 0 && var.datacenter != "")
      error_message = "datacenter is only used for powerVS spokes.  The datacenter configuration is being ignored"
    }
  }
}
