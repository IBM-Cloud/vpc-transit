# normal
provider "ibm" {
  region = local.provider_region
}

# powerVS
locals {
  # most power regions can be determined by removing the last 2 letters except these:
  non_standard_regions = {
    "dal" : "us-south"
    "wdc" : "us-east"
  }
  _region      = substr(local.datacenter, 0, length(local.datacenter) - 2)
  power_region = lookup(local.non_standard_regions, local._region, local._region)
}
provider "ibm" {
  alias  = "power"
  region = local.power_region
  zone   = local.datacenter
}
