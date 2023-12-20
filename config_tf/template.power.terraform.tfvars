# Defaults that work for a 1 spoke VPC + 1 spoke PowerVS environment over VPN

resource_group_name = "Default" # YOUR resource group

# optionally change these
basename   = "abc"      # Your initials (or unique values in your account)
region     = "us-south" # change as desired
datacenter = "dal10"    # must be a PowerVS Power Edge Router (PER) supported datacenter

# --------------------------------
# do not change these if following the steps in the solution tutorial (VPN based)
# Choose either vpn=true, firewall=false OR vpn=false, firewall=true
#VPN:
vpn      = true
firewall = false

#Direct link simulation:
#vpn      = false
#firewall = true

# do not change these --------------------------------
spoke_count_vpc              = 0
spoke_count_power            = 1
zones                        = 1
all_firewall                 = false
make_postgresql              = true
firewall_nlb                 = false
number_of_firewalls_per_zone = 1
test_lbs                     = false
