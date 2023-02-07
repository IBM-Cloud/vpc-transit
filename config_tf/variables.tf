variable "ssh_key_name" {}
variable "resource_group_name" {}
variable "basename" {}
variable "region" {}
variable "spoke_count" {}
variable "enterprise_phantom_address_prefixes_in_transit" {
  type = bool
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
variable "image_name" {
  default = "ibm-ubuntu-22-04-1-minimal-amd64-3"
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
