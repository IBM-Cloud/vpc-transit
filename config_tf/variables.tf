variable "ibmcloud_api_key" {}
variable "ssh_key_name" {}
variable "resource_group_name" {}
variable "basename" {}
variable "region" {}
variable "spoke_count" {}
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
  type = bool
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
  default = "ibm-ubuntu-18-04-1-minimal-amd64-2"
}

# firewall implementation
# is there a firewall
variable "firewall" {
  type = bool
}
# is there a network load balancer for the firewall?
variable "firewall_lb" {
  type = bool
}
variable "number_of_firewalls_per_zone" {
  type = number
}

# test load balancers
variable "test_lbs" {
  type    = bool
  default = false
}
