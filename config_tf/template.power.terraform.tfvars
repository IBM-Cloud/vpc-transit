# Defaults that work for a 1 spoke VPC + 1 spoke PowerVS environment over VPN

resource_group_name = "Default" # YOUR resource group

# optionally change these
basename   = "abc"      # Your initials (or unique values in your account)
region     = "us-south" # change as desired
datacenter = "dal10"    # must be a PowerVS Power Edge Router (PER) supported datacenter

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
