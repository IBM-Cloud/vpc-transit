# spokes - power spokes

data "terraform_remote_state" "config" {
  backend = "local"

  config = {
    path = "../config_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "transit_spoke_tgw" {
  backend = "local"

  config = {
    path = "../transit_spoke_tgw_tf/terraform.tfstate"
  }
}
data "terraform_remote_state" "test_instances" {
  backend = "local"

  config = {
    path = "../test_instances_tf/terraform.tfstate"
  }
}
locals {
  config_tf          = data.terraform_remote_state.config.outputs
  tls_public_key     = local.config_tf.tls_public_key
  settings           = local.config_tf.settings
  spokes_zones       = local.config_tf.spokes_zones
  spokes_zones_power = local.config_tf.spokes_zones_power
  tags               = local.settings.tags
  transit_spoke_tgw  = data.terraform_remote_state.transit_spoke_tgw.outputs
  tg_gateway         = local.transit_spoke_tgw.tg_gateway
  test_instances     = data.terraform_remote_state.test_instances.outputs
  transit            = local.test_instances.transit

  provider_region = local.settings.region
  datacenter      = local.settings.datacenter

  zones_subnets = [for spoke_number, spokes_zones in local.spokes_zones : [for zone_number, zone in spokes_zones : [for subnet_number, subnet in zone.subnets : {
    subnet_number = subnet_number # subnet in zone: 0,1,2,3
    zone          = subnet.zone   # us-south-1
    cidr          = subnet.cidr
    name          = "${local.settings.basename}-spoke${spoke_number}-z${zone_number + 1}-s${subnet_number}"
  }]]]
}

# Power spokes indexed by spoke number (these start counting after the vpc spokes)
module "spokes_power" {
  for_each                  = { for spoke, zones in local.spokes_zones_power : spoke + local.settings.spoke_count_vpc => zones }
  source                    = "../modules/power"
  name                      = "${local.settings.basename}-spoke${each.key}"
  settings                  = local.settings
  zones_subnets             = local.zones_subnets[each.key]
  make_firewall_route_table = false
}

output "powers" {
  value = [for spoke in module.spokes_power : spoke.power]
}

resource "ibm_tg_connection" "spokes_power" {
  // this could be indexed by spoke number but currently 0 based
  for_each     = { for spoke_number, power in module.spokes_power : spoke_number => power.power }
  network_type = "power_virtual_server"
  gateway      = local.tg_gateway.id
  name         = each.value.name
  network_id   = each.value.crn
}

output "tg_gateway" {
  value = {
    id   = local.tg_gateway.id
    name = local.tg_gateway.name
    connections = { for key, value in ibm_tg_connection.spokes_power : key => {
      name          = value.name
      connection_id = value.connection_id
    } }
  }
}

# * need to choose either a personal key or the temporary key created by terraform
#data "ibm_pi_key" "personal" {
#  pi_key_name          = var.settings.ssh_key_name
#  pi_cloud_instance_id = var.power.guid
#}

# put the key into the first power spoke (it will be visible in all spokes)
resource "ibm_pi_key" "ssh_key_tmp" {
  pi_key_name          = local.settings.basename
  pi_ssh_key           = local.tls_public_key
  pi_cloud_instance_id = module.spokes_power[local.settings.spoke_count_vpc].power.guid
}


module "spokes_power_instances" {
  for_each     = { for spoke_number, power in module.spokes_power : spoke_number => power.power }
  source       = "./power_test_instances_tf"
  settings     = local.settings
  power        = each.value
  ssh_key_name = ibm_pi_key.ssh_key_tmp.pi_key_name
}
output "spokes_power_instances" {
  value = module.spokes_power_instances
}

output "fixpower" {
  value = [for spoke_number, power_instances in module.spokes_power_instances : {
    for worker_name, worker in power_instances.workers : worker_name =>
    <<-EOS
      # ssh -J root@${values(local.transit.workers)[0].fip} root@${worker.primary_ipv4_address}
      ssh -oProxyCommand="ssh -W %h:%p -i ../config_tf/id_rsa root@${values(local.transit.workers)[0].fip}" -i ../config_tf/id_rsa root@${worker.primary_ipv4_address}
      ip route add 10.0.0.0/8 via ${module.spokes_power[spoke_number].power.network_private.pi_gateway} dev eth0
      ip route add 172.16.0.0/12 via ${module.spokes_power[spoke_number].power.network_private.pi_gateway} dev eth0
      ip route add 192.168.0.0/16 via ${module.spokes_power[spoke_number].power.network_private.pi_gateway} dev eth0
      ip route change default via ${module.spokes_power[spoke_number].power.network_public.pi_gateway} dev eth1
      exit
      # it is now possible to ssh directly to the public IP address
      ssh -i ../config_tf/id_rsa root@${worker.fip}
      # execute the rest of these commands to install nginx for testing
      ${power_instances.user_data}
    EOS
  }]
}

/*
      ip route add 10.0.0.0/8 via ${module.spokes_power[spoke_number].power.network_private.pi_gateway} dev eth0
      ip route add 172.16.0.0/12 via ${power.power.network_private.pi_gateway} dev eth0
      ip route add 192.168.0.0/16 via ${power.power.network_private.pi_gateway} dev eth0
      ip route change default via ${power.power.network_public.pi_gateway} dev eth1
      */
