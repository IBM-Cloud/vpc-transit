# must adjust these values to your environment:
ssh_key_name        = "YOUR_VPC_INSTANCE_SSH_KEY" # YOUR ssh key
resource_group_name = "Default"                   # YOUR resource group

# optionally change these
basename = "tvpc"     # change if you wish, maybe your initials
region   = "us-south" # change as desired

# In part 1 of the tutorial only enterprise <-> spoke traffic flows through the firewall-router (all_firewall = false).
# In part 2 of the tutorial set all_firewall to true to also route
# enterprise <-> transit, spoke <-> spoke and spoke <-> transit through the firewall (all_firewall = true).
# After changing this value re-apply all layers:  ./apply.sh : LAST_LAYER
all_firewall = false

# If following the tutorial do not initially modify the values below
make_redis  = true
spoke_count = 2 #set to 0 to remove spokes
zones       = 3

# firewall_nlb is set to true to create a NLB that distributes load to the actual firewall-routers
# If firewall_nlb s true set the number of firewall instances
firewall_nlb                 = false
number_of_firewalls_per_zone = 1

# test load balancers?  If true: 5 load balancers are created in spoke0, nlb, alb and alb regional
test_lbs = false
