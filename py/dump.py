import collections
import procin
import typer
import rich
from rich import print
console = rich.console.Console()


class FromDict:
    def __init__(self, entries):
        self.entries = entries
        self.__dict__.update(**entries)

    def __len__(self):
        return len(self.entries)
    

class TerraformOutput:
  def __init__(self):
    # from apply.sh
    all="config_tf enterprise_tf transit_tf spokes_tf test_instances_tf test_lbs_tf transit_spoke_tgw_tf enterprise_link_tf firewall_tf spokes_egress_tf all_firewall_tf all_firewall_asym_tf dns_tf vpe_transit_tf vpe_spokes_tf vpe_dns_forwarding_rules_tf"
    self.tf_dir_outputs = collections.OrderedDict()
    for tf_dir_name in all.split():
      try:
        self.tf_dir_outputs[tf_dir_name] = {key: value["value"] for key, value in tf_output(tf_dir_name).items()}
      except:
        self.tf_dir_outputs[tf_dir_name] = {}

  def __getattr__(self, name):
      value = FromDict(self.tf_dir_outputs[name])
      self.__dict__.update({name: value})
      return value

  def outputs(self, tf_dir):
    self.tf_dir_outputs[tf_dir]





#class TerraformOutput:
#    """delay reading the terraform output until it is requested.  Then cache the results.
#    The top level variables are read into a FromDict class.
#    Access terraform top level variables like: tf_dirs.config_tf.settings"""
#
#    def __getattr__(self, name):
#        value = FromDict(
#            **{key: value["value"] for key, value in tf_output(name).items()}
#        )
#        self.__dict__.update({name: value})
#        return value

def tf_output(dir):
    c = procin.Command(json=True)
    tf = c.run(["terraform", "output", f"-state={dir}/terraform.tfstate", "-json"])
    return tf


def dump_vpc_instances(name, instances, vpc):
    print(f"vpc - {name} {vpc['id']}")
    for instance_name, instance in instances["workers"].items():
      print(f'  {instance["name"]} {instance["primary_ipv4_address"]} {instance["fip"]} {instance["id"]}')

def dump_test_instances(tf_dirs):
    if len(tf_dirs.test_instances_tf) == 0:
      return
    dump_vpc_instances("enterprise", tf_dirs.test_instances_tf.enterprise, tf_dirs.enterprise_tf.vpc)
    dump_vpc_instances("transit", tf_dirs.test_instances_tf.transit, tf_dirs.transit_tf.vpc)
    for spoke_number, spoke in tf_dirs.test_instances_tf.spokes.items():
      dump_vpc_instances(f"spoke{spoke_number}", spoke, tf_dirs.spokes_tf.vpcs[int(spoke_number)])

def dump_firewall(tf_dirs):
    print("firewalls in transit")
    try:
      firewall_zones = tf_dirs.firewall_tf.zones
      for zone_number, zone in firewall_zones.items():
        print(f"  firewall_ip: {zone['firewall_ip']}")
        for instance_name, instance in zone['firewalls'].items():
          print(f'    {instance["name"]} {instance["primary_ipv4_address"]} {instance["fip"]} {instance["id"]}')
    except:
        print(f"  none")

def dump_vpe_resource(resource):
  print(f'{resource["type"]}')
  for ip in  resource["virtual_endpoint_gateway"]["ips"]:
    print(f'  {ip["address"]} {ip["name"]}')

def dump_vpe(resources):
  for resource in resources:
    if 'virtual_endpoint_gateway' in resource:
      dump_vpe_resource(resource)

def dump_vpes(tf_dirs):
    if len(tf_dirs.vpe_transit_tf) == 0:
      print(f'vpes: NONE')
      return
    resources = tf_dirs.vpe_transit_tf.resources
    dump_vpe(resources)

def dump_zones(name, zones):
    print(f'zone {name}')
    for zone in zones:
      print(f'  address_prefix')
      for address_prefix in zone['address_prefixes']:
        print(f'    {address_prefix["cidr"]}')
      print(f'  subnet')
      for subnet in zone['subnets']:
        print(f'    {subnet["cidr"]}')

def dump_tgw(tgw):
    print(f' {tgw["name"]} {tgw["id"]}')
    for connection_name, connection in tgw["connections"].items():
      print(f'    {connection["name"]} {connection["connection_id"]}')

def dump_lb(lb_name, lb_obj):
  print(f"  {lb_name}")
  lb = lb_obj["lb"]
  workers = lb_obj["workers"]
  instances = lb_obj["instances"]
  print(f"    name: {lb['name']}")
  print(f"    hostname: {lb['hostname']}")
  print(f"    private_ips:")
  for private_ip in lb['private_ips']:
    print(f"      {private_ip}")

  print(f"    workers:")
  for worker in workers.values():
    print(f"      {worker['primary_ipv4_address']} {worker['fip']} {worker['name']}")

def dump_lbs(tf_dirs):
    print('lbs')
    if len(tf_dirs.test_lbs_tf) == 0:
        print('  no lbs')
        return
    for lb_name, lb in tf_dirs.test_lbs_tf.lbs.items():
      dump_lb(lb_name, lb)
  
def dump_tgws(tf_dirs):
    print('tgws')
    if len(tf_dirs.enterprise_link_tf) == 0:
        print('  no enterprise_link_tf')
    else:
        dump_tgw(tf_dirs.enterprise_link_tf.tg_gateway)
    if len(tf_dirs.transit_spoke_tgw_tf) == 0:
        print('  no transit_spoke_tgw_tf')
    else:
        dump_tgw(tf_dirs.transit_spoke_tgw_tf.tg_gateway)
  

def dump_settings(settings):
  print("settings:")
  for setting in ["subnet_worker", "subnet_dns", "subnet_vpe", "subnet_fw"]:
    print(f'  {setting} {settings[setting]}')

def dump_config(tf_dirs):
    if len(tf_dirs.config_tf) == 0:
      return
    settings = tf_dirs.config_tf.settings
    dump_settings(settings)
    transit_zones = tf_dirs.config_tf.transit_zones
    dump_zones("transit", transit_zones)

def dump_normal(tf_dirs):
    dump_lbs(tf_dirs)
    dump_tgws(tf_dirs)
    dump_vpes(tf_dirs)
    dump_config(tf_dirs)
    dump_firewall(tf_dirs)
    dump_test_instances(tf_dirs)


def dump_each_layer(tf_dirs, details):
  table = rich.table.Table(title="tf dir outputs?")
  table.add_column("dir", justify="right", no_wrap=True)
  table.add_column("output?", justify="left", no_wrap=True)
  for tf_dir, outputs in tf_dirs.tf_dir_outputs.items():
      if details:
        print(f'{tf_dir}:')
        for key, value in outputs.items():
          print(f'{key}: ', end="")
          print(outputs)
      table.add_row(tf_dir, str(len(outputs) != 0))
  print(table)

def dump():
    tf_dirs = TerraformOutput()
    dump_each_layer(tf_dirs, flag_all())
    dump_normal(tf_dirs)

app = typer.Typer()
g_all = False
def flag_all() -> bool:
  return g_all

@app.command()
def main(all: bool = typer.Option(False, help="complete dump with a lot of verbosity")):
  global g_all
  g_all = all
  dump()

if __name__ == "__main__":
    app()
