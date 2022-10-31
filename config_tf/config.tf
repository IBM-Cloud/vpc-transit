data "ibm_is_ssh_key" "ssh_key" {
  name = var.ssh_key_name
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

locals {
  provider_region = var.region
  spoke_count     = var.spoke_count
  zones           = var.zones
  # Each VPC is first broken into zones indexed 0..3
  # the zone is the first break down.  Terraform will refer to them as zone 0, 1, 2 (1 and 2 optional)
  # zone 0 - 10.0.0.0/16 us-south-1
  # zone 1 - 10.1.0.0/16 us-south-2
  # zone 2 - 10.2.0.0/16 us-south-3

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

# zones has the description for each zone.  subnets, address prefixes, entire cidr block
output "enterprise_zones" {
  value = [for zone_number, zone_cidr in local.enterprise_zone_cidrs : {
    zone             = zone_cidr.zone
    cidr             = zone_cidr.cidr
    subnets          = local.enterperise_zone_subnets[zone_number]
    address_prefixes = local.enterperise_zone_subnets[zone_number]
  }]
}

# cloud configuration is a map wher cloud[0] is transit and cloud[1..n] are the spokes
locals {
  cloud_cidr = "10.0.0.0/8"

  # list of ciders for each zone
  cloud_zones_cidr = [for zone_number in range(local.zones) : {
    cidr = cidrsubnet(local.cloud_cidr, 8, zone_number)
    zone = "${var.region}-${zone_number + 1}" # not zero based, all other zone number are zero based
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
      address_prefixes = [for subnet in range(4) : {
        cidr = cidrsubnet(zone_cidr.cidr, 2, subnet)
        zone = zone_cidr.zone
      }]
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

output "settings" {
  value = {
    myip = data.external.ifconfig_me.result.ip # replace with your IP if ifconfig.me does not work
    # todo used for security groups seems off
    cloud_cidr       = local.cloud_cidr
    cloud_zones_cidr = local.cloud_zones_cidr
    enterprise_cidr  = local.enterprise_cidr
    user             = "root"
    subnet_worker    = local.subnet_worker
    subnet_fw        = local.subnet_fw
    subnet_dns       = local.subnet_dns
    subnet_vpe       = local.subnet_vpe
    tags = [
      "basename:${var.basename}",
      replace("dir:${abspath(path.root)}", "/", "_"),
    ]
    region                       = var.region
    resource_group_name          = var.resource_group_name
    resource_group_id            = data.ibm_resource_group.group.id
    vpn                          = var.vpn
    vpn_route_based              = var.vpn_route_based
    ssh_key                      = data.ibm_is_ssh_key.ssh_key
    basename                     = var.basename
    image_id                     = data.ibm_is_image.ubuntu.id
    profile                      = var.profile
    make_redis                   = var.make_redis
    make_postgresql              = var.make_postgresql
    make_cos                     = var.make_cos
    firewall                     = var.firewall
    firewall_lb                  = var.firewall_lb
    number_of_firewalls_per_zone = var.number_of_firewalls_per_zone
    all_firewall                 = true
  }
}
