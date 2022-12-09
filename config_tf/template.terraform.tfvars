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

# firewall is optional.  If firewall is true firewall_lb is applied, if firewall_lb is true set the number of firewall instances
firewall                     = true
firewall_lb                  = false
number_of_firewalls_per_zone = 1

# if the firewall is true only enterprise traffic flows through the firewall.  Unless all_firewall is true.
# when true spoke <-> spoke and spoke <-> transit will also pass through the firewall.
# if following along with the tutorial keep this as false, there is a step in the tutorial where this is changed to true
all_firewall = false

# test load balancers?  If true: 5 load balancers are created in spoke0, nlb, alb and alb regional
test_lbs = false
