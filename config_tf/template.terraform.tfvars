# must adjust these values to your environment:
ssh_key_name        = "YOUR_VPC_INSTANCE_SSH_KEY" # YOUR ssh key
resource_group_name = "Default"                   # YOUR resource group

# optionally change these
basename = "tvpc"     # change if you wish, maybe your initials
region   = "us-south" # change as desired

# monification of the rest are not required for the initial steps of the tutorial
make_redis  = true
spoke_count = 2 #set to 0 to remove spokes
zones       = 2

# firewall is optional.  If true firewall NLB is optional, if lb true set the number of firewalls
firewall                     = true
firewall_lb                  = false
number_of_firewalls_per_zone = 1

vpn             = false # vpn or tgw enterprise link to transit, false=tgw
vpn_route_based = false # vpn route not applicable to this tutorial, must be false for now
