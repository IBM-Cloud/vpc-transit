# Defaults that work for a 1 spoke VPC + 1 spoke PowerVS environment over VPN

resource_group_name = "Default" # YOUR existing resource group name

# optionally change these
basename = "abc" # Prefix for all resources created

region     = "us-south" # change as desired like eu-es
datacenter = "dal10"    # PowerVS Power Edge Router (PER) supported datacenter in the same region, like mad02, in the same region as eu-es

# --------------------------------
# do not change these for the VPN solution tutorial
#VPN:
vpn      = true
firewall = false

# No changes required for the VPN solution tutorial --------------------------------
spoke_count_vpc   = 0
spoke_count_power = 1
zones             = 1
make_postgresql   = true
test_lbs          = false

#  Must not change for VPN based configuration (no firewall in VPN configuration)
all_firewall                 = false
firewall_nlb                 = false
number_of_firewalls_per_zone = 1
