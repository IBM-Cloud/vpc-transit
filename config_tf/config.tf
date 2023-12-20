data "ibm_is_ssh_key" "ssh_key" {
  count = var.ssh_key_name == "" ? 0 : 1
  name  = var.ssh_key_name
}

data "ibm_is_image" "ubuntu" {
  name = var.image_name
}

data "external" "ifconfig_me" {
  program = ["bash", "-c", <<-EOS
    echo '{"ip": "'$(curl ifconfig.me)'"}'
  EOS
  ]
}

data "ibm_resource_group" "group" {
  name = var.resource_group_name
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "ssh_key_tmp_private" {
  content         = tls_private_key.private_key.private_key_pem
  filename        = "${abspath(path.root)}/id_rsa"
  file_permission = "0600"
}

resource "local_file" "ssh_key_tmp_public" {
  content         = tls_private_key.private_key.public_key_pem
  filename        = "${abspath(path.root)}/id_rsa.pub"
  file_permission = "0644"
}

resource "ibm_is_ssh_key" "ssh_key_tmp" {
  name           = var.basename
  resource_group = data.ibm_resource_group.group.id
  public_key     = tls_private_key.private_key.public_key_openssh
}

locals {
  ssh_key_ids       = var.ssh_key_name == "" ? [ibm_is_ssh_key.ssh_key_tmp.id] : [data.ibm_is_ssh_key.ssh_key[0].id, ibm_is_ssh_key.ssh_key_tmp.id]
  provider_region   = var.region
  spoke_count       = var.spoke_count_vpc + var.spoke_count_power
  spoke_count_power = var.spoke_count_power
  spoke_count_vpc   = var.spoke_count_vpc
  zones             = var.zones
  # Each VPC is first broken into zones indexed 0..2
  # the zone is the first break down.  Terraform will refer to them as zone 0, 1, 2 (1 and 2 optional)
  # They cidr blocks are 1,2,3
  # zone 0 - 10.1.0.0/16 us-south-1
  # zone 1 - 10.2.0.0/16 us-south-2
  # zone 2 - 10.3.0.0/16 us-south-3

  # 4 subnets:
  subnet_worker = 0 # worker instances
  subnet_dns    = 1 # dns custom resolvers
  subnet_vpe    = 2 # vpc private endpoint gateways
  subnet_fw     = 3 # firewall (transit only)

  # enterprise zones are the full cidr block for each zone: 192.168.z.0/24
  # enterprise zone subnets for the two subnets in each zone
  enterprise_cidr = "192.168.0.0/16"
  enterprise_zone_cidrs = [for zone_number in range(local.zones) : {
    cidr = cidrsubnet(local.enterprise_cidr, 8, zone_number)
    zone = "${var.region}-${zone_number + 1}"
  }]
  enterperise_zone_subnets = [for zone_cidr in local.enterprise_zone_cidrs : [
    for s in [local.subnet_worker, local.subnet_dns] : {
      cidr = cidrsubnet(zone_cidr.cidr, 1, s)
      zone = zone_cidr.zone
  }]]
}

# public key
output "tls_public_key" {
  value = tls_private_key.private_key.public_key_openssh
}

# zones has the description for each zone.  subnets, address prefixes, entire cidr block
output "enterprise_zones" {
  value = [for zone_number, zone_cidr in local.enterprise_zone_cidrs : {
    zone             = zone_cidr.zone
    cidr             = zone_cidr.cidr
    subnets          = local.enterperise_zone_subnets[zone_number]
    address_prefixes = local.enterperise_zone_subnets[zone_number] # todo
  }]
}

# cloud configuration is a map wher cloud[0] is transit and cloud[1..n] are the spokes
locals {
  cloud_cidr = "10.0.0.0/8"

  # list of ciders for each zone
  cloud_zones_cidr = [for zone_number in range(local.zones) : {
    cidr = cidrsubnet(local.cloud_cidr, 8, zone_number + 1)
    zone = "${var.region}-${zone_number + 1}"
  }]

  # vpcs is used instead of spokes since it includes transit and all the spokes
  # transit = vpcs[0] and spokes[0..2] = vpcs[1..3]
  cloud_vpcs_zones_cidrs = [for i in range(local.spoke_count + 1) : [
    for zone_cidr in local.cloud_zones_cidr : {
      cidr = cidrsubnet(zone_cidr.cidr, 8, i)
      zone = zone_cidr.zone
  }]]

  # cloud_vpcs_zones[spoke][zone][subnet_worker] - subnet for workers in zone
  # cloud_vpcs_zones[*][zone][subnet_dns] - all subnets (in all zones) available for dns resolvers
  cloud_vpcs_zones = [for zone_ciders in local.cloud_vpcs_zones_cidrs : [
    for zone_cidr in zone_ciders : {
      zone = zone_cidr.zone
      cidr = zone_cidr.cidr
      subnets = [for subnet in range(4) : {
        cidr = cidrsubnet(zone_cidr.cidr, 2, subnet)
        zone = zone_cidr.zone
      }]
  }]]
}

output "transit_zones" {
  value = local.cloud_vpcs_zones[0]
}

output "spokes_zones" {
  value = [for spoke in range(local.spoke_count) : local.cloud_vpcs_zones[spoke + 1]]
}

# VPCs start at spoke0 consuming CIDR blocks following the transit
output "spokes_zones_vpc" {
  value = [for spoke in range(0, local.spoke_count_vpc) : local.cloud_vpcs_zones[spoke + 1]]
}

# Powers start after the VPCS consuming CIDR blocks following the VPCs
output "spokes_zones_power" {
  value = [for spoke in range(local.spoke_count_vpc, local.spoke_count) : local.cloud_vpcs_zones[spoke + 1]]
}

output "settings" {
  value = {
    myip              = data.external.ifconfig_me.result.ip # replace with your IP if ifconfig.me does not work
    cloud_cidr        = local.cloud_cidr
    cloud_zones_cidr  = local.cloud_zones_cidr
    enterprise_cidr   = local.enterprise_cidr
    user              = "root"
    subnet_worker     = local.subnet_worker
    subnet_fw         = local.subnet_fw
    subnet_dns        = local.subnet_dns
    subnet_vpe        = local.subnet_vpe
    spoke_count       = local.spoke_count
    spoke_count_vpc   = local.spoke_count_vpc
    spoke_count_power = local.spoke_count_power
    tags = [
      "basename:${var.basename}",
      "dir: ${lower(replace(replace("${abspath(path.root)}", "/", "_"), ":", "_"))}",
    ]
    zones                        = local.zones
    region                       = var.region
    datacenter                   = var.datacenter
    resource_group_name          = var.resource_group_name
    resource_group_id            = data.ibm_resource_group.group.id
    vpn                          = var.vpn
    vpn_route_based              = var.vpn_route_based
    ssh_key_ids                  = local.ssh_key_ids
    ssh_key_name                 = var.ssh_key_name
    basename                     = var.basename
    image_id                     = data.ibm_is_image.ubuntu.id
    profile                      = var.profile
    make_redis                   = var.make_redis
    make_postgresql              = var.make_postgresql
    make_cos                     = var.make_cos
    firewall                     = var.firewall
    firewall_nlb                 = var.firewall_nlb
    number_of_firewalls_per_zone = var.number_of_firewalls_per_zone
    all_firewall                 = var.all_firewall
    test_lbs                     = var.test_lbs
  }
}
