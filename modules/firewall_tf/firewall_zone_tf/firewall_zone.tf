# transit zone

variable "tags" {}
variable "vpc_id" {}
variable "subnet_firewall" {}
variable "resource_group_id" {}
variable "ssh_key_ids" {}
variable "profile" {}
variable "image_id" {}
variable "firewall_nlb" {}
variable "number_of_firewalls_per_zone" {}
variable "user_data" {}
variable "name" {}
variable "security_groups" {}

resource "ibm_is_lb" "zone" {
  count      = var.firewall_nlb ? 1 : 0
  route_mode = true
  name       = var.name
  subnets    = [var.subnet_firewall.id]
  profile    = "network-fixed"
  type       = "private"
}
resource "ibm_is_lb_listener" "zone" {
  count        = var.firewall_nlb ? 1 : 0
  lb           = ibm_is_lb.zone[0].id
  default_pool = ibm_is_lb_pool.zone[0].id
  protocol     = "tcp"
  #port_min         = 1
  #port_max         = 65535
}

resource "ibm_is_lb_pool" "zone" {
  count                    = var.firewall_nlb ? 1 : 0
  name                     = var.name
  lb                       = ibm_is_lb.zone[0].id
  algorithm                = "round_robin"
  protocol                 = "tcp"
  session_persistence_type = "source_ip"
  health_delay             = 60
  health_retries           = 5
  health_timeout           = 30
  health_type              = "http"
  health_monitor_url       = "/"
  #health_monitor_port    = 80
}
resource "ibm_is_lb_pool_member" "zone" {
  for_each  = var.firewall_nlb ? ibm_is_instance.firewall : {}
  lb        = ibm_is_lb.zone[0].id
  pool      = element(split("/", ibm_is_lb_pool.zone[0].id), 1)
  port      = 80
  target_id = each.value.id
  #target_address = each.value.primary_network_interface[0].primary_ipv4_address
  #weight = 50
}

# one fore each firewall replica
resource "ibm_is_instance" "firewall" {
  for_each       = { for key in range(var.number_of_firewalls_per_zone) : key => key }
  tags           = var.tags
  resource_group = var.resource_group_id
  name           = "${var.name}-${each.value}"
  image          = var.image_id
  profile        = var.profile
  vpc            = var.vpc_id
  zone           = var.subnet_firewall.zone
  keys           = var.ssh_key_ids
  primary_network_interface {
    subnet            = var.subnet_firewall.id
    security_groups   = var.security_groups
    allow_ip_spoofing = true
  }
  user_data = <<-EOT
    ${var.user_data}
    echo ${var.name} > /var/www/html/instance
    sysctl -w net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf 
    #
    cat > /etc/iptables.no << 'EOF'
    *filter
    :INPUT ACCEPT
    :OUTPUT ACCEPT
    :FORWARD DROP
    COMMIT
    EOF
    cat > /etc/iptables.all << 'EOF'
    *filter
    :INPUT ACCEPT
    :OUTPUT ACCEPT
    :FORWARD ACCEPT
    -A FORWARD -j LOG --log-prefix "fw-router: "
    COMMIT
    EOF
    iptables-restore /etc/iptables.all
  EOT
}

resource "ibm_is_floating_ip" "firewall" {
  for_each       = ibm_is_instance.firewall
  tags           = var.tags
  resource_group = var.resource_group_id
  name           = each.value.name
  target         = each.value.primary_network_interface[0].id
}

output "zone" {
  value = var.subnet_firewall.zone
}
output "firewalls" {
  value = { for index, instance in ibm_is_instance.firewall : instance.name => {
    id                   = instance.id
    name                 = instance.name
    subnet_name          = instance.name
    fip                  = ibm_is_floating_ip.firewall[index].address
    zone                 = instance.zone
    primary_ipv4_address = instance.primary_network_interface[0].primary_ip[0].address
  } }
}

# load balancer or if no load balancer the IP of of the firewall
output "firewall_ip" {
  value = var.firewall_nlb ? ibm_is_lb.zone[0].private_ips[0] : ibm_is_instance.firewall[0].primary_network_interface[0].primary_ip[0].address
  precondition {
    condition     = (var.number_of_firewalls_per_zone == 1) || (var.firewall_nlb && var.number_of_firewalls_per_zone >= 1)
    error_message = "There must be at least one firewall.  If there is no load balancer there must be exactly one firewall"
  }
}
