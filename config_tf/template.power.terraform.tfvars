# Defaults that work for a 1 spoke VPC + 1 spoke PowerVS environment over VPN
ssh_key_name        = ""         # Optional additional ssh key added to VPC instances.  A temporary ssh key will be added to all instances.
resource_group_name = "feedback" # YOUR resource group

# optionally change these
basename   = "abc"      # change if you wish, maybe your initials
region     = "us-south" # change as desired
datacenter = "dal10"

# Choose either vpn=true, firewall=false OR vpn=false, firewall=true
#VPN:
vpn      = true
firewall = false

#Direct link simulation:
#vpn      = false
#firewall = true


# do not change these --------------------------------
spoke_count                                    = 2
spoke_count_power                              = 1
zones                                          = 1
enterprise_phantom_address_prefixes_in_transit = true
all_firewall                                   = false
make_postgresql                                = true
firewall_nlb                                   = false
number_of_firewalls_per_zone                   = 1
test_lbs                                       = false
