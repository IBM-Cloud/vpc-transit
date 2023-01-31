# load balancer workers

variable "settings" {}
variable "vpc" {}
variable "name" {}
variable "zone_number" {}
variable "lb_type" {}

locals {
  tags                         = var.settings.tags
  resource_group_id            = var.settings.resource_group_id
  security_group_inbound_cidrs = [var.settings.cloud_cidr, var.settings.enterprise_cidr]
  ssh_key_ids                  = var.settings.ssh_key_ids
  image_id                     = var.settings.image_id
  profile                      = var.settings.profile

  # regional alb is spread across all of the zones, the zonal will put two lb appliances in the same zone
  worker_subnets = var.lb_type == "alb-regional" ? [
    for _, zone in var.vpc.zones : zone.subnets[var.settings.subnet_worker]] : [
    var.vpc.zones[var.zone_number].subnets[var.settings.subnet_worker],
    var.vpc.zones[var.zone_number].subnets[var.settings.subnet_worker]
  ]
  name = var.settings.basename

  security_groups = [var.vpc.default_security_group]

  number_of_lb_test_instances = 1
  user_data                   = file("${path.module}/../../modules/user_data.sh")
  instances = flatten([for subnet_number, subnet in [local.worker_subnets[0]] : # put all of the workers in one subnet for now, regional alb is effected
    [for worker_number in range(local.number_of_lb_test_instances) : {
      tags            = local.tags
      resource_group  = local.resource_group_id
      name            = "${local.name}-lbtw-${var.name}-s${subnet.name}-w${worker_number}"
      image           = local.image_id
      profile         = local.profile
      vpc             = var.vpc.id
      zone            = subnet.zone
      keys            = local.ssh_key_ids
      subnet          = subnet.id
      security_groups = local.security_groups
    }]
  ])
}

resource "ibm_is_instance" "workers" {
  for_each       = { for inum, instance in zipmap(range(length(local.instances)), local.instances) : inum => instance }
  tags           = each.value.tags
  resource_group = each.value.resource_group
  name           = each.value.name
  image          = each.value.image
  profile        = each.value.profile
  vpc            = each.value.vpc
  zone           = each.value.zone
  keys           = each.value.keys
  primary_network_interface {
    subnet          = each.value.subnet
    security_groups = each.value.security_groups
  }
  user_data = replace(local.user_data, "__NAME__", each.value.name)
}

resource "ibm_is_floating_ip" "workers" {
  for_each       = ibm_is_instance.workers
  tags           = each.value.tags
  resource_group = each.value.resource_group
  name           = each.value.name
  target         = each.value.primary_network_interface[0].id
}

output "workers" {
  value = {
    for worker_id, worker in ibm_is_instance.workers : worker_id => {
      id                   = worker.id
      name                 = worker.name
      subnet_name          = worker.name
      fip                  = ibm_is_floating_ip.workers[worker_id].address
      primary_ipv4_address = worker.primary_network_interface[0].primary_ipv4_address
      zone                 = worker.zone
    }
  }
}

output "instances" {
  value = local.instances
}


resource "ibm_is_lb" "worker" {
  route_mode = false
  name       = "${local.name}-${var.name}"
  subnets    = [for subnet in local.worker_subnets : subnet.id]
  type       = "private"
  profile    = var.lb_type == "nlb-zonal" ? "network-fixed" : null
}

output "lb" {
  value = {
    private_ips = ibm_is_lb.worker.private_ips
    hostname    = ibm_is_lb.worker.hostname
    name        = ibm_is_lb.worker.name
    type        = ibm_is_lb.worker.type
  }
}

resource "ibm_is_lb_pool" "worker" {
  name                     = local.name
  lb                       = ibm_is_lb.worker.id
  algorithm                = "round_robin"
  protocol                 = "tcp"
  session_persistence_type = "source_ip"
  health_delay             = 60
  health_retries           = 5
  health_timeout           = 30
  health_type              = "tcp"
  health_monitor_url       = "/"
  #health_monitor_port    = 80
}

resource "ibm_is_lb_pool_member" "worker_alb" {
  for_each       = var.lb_type == "nlb-zonal" ? {} : ibm_is_instance.workers
  lb             = ibm_is_lb.worker.id
  pool           = element(split("/", ibm_is_lb_pool.worker.id), 1)
  port           = 80
  target_address = each.value.primary_network_interface[0].primary_ipv4_address
  weight         = 50
}

resource "ibm_is_lb_pool_member" "worker_nlb" {
  for_each  = var.lb_type == "nlb-zonal" ? ibm_is_instance.workers : {}
  lb        = ibm_is_lb.worker.id
  pool      = element(split("/", ibm_is_lb_pool.worker.id), 1)
  port      = 80
  target_id = each.value.id
  weight    = 50
}

resource "ibm_is_lb_listener" "worker" {
  lb           = ibm_is_lb.worker.id
  default_pool = ibm_is_lb_pool.worker.id
  protocol     = "tcp"
  port         = 80
  #port_min         = 1
  #port_max         = 65535
}
