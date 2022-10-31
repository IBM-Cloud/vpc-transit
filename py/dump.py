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
    all="config_tf enterprise_tf transit_tf spokes_tf test_instances_tf transit_spoke_tgw_tf enterprise_link_tf firewall_tf spokes_egress_tf all_firewall_tf dns_tf vpe_transit_tf vpe_spokes_tf"
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


def dump_vpc_instances(name, instances):
    print(f"vpc - {name}")
    for instance_name, instance in instances["workers"].items():
      print(f'  {instance["name"]} {instance["primary_ipv4_address"]} {instance["fip"]}')

def dump_test_instances(tf_dirs):
    dump_vpc_instances("enterprise", tf_dirs.test_instances_tf.enterprise)
    dump_vpc_instances("transit", tf_dirs.test_instances_tf.transit)
    for spoke_number, spoke in tf_dirs.test_instances_tf.spokes.items():
      dump_vpc_instances(f"spoke{spoke_number}", spoke)

def dump_firewall(tf_dirs):
    print("firewall in transit")
    try:
      firewall_zones = tf_dirs.firewall_tf.zones
      for zone in firewall_zones:
        print(f"  {zone}")
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
    dump_config(tf_dirs)
    dump_test_instances(tf_dirs)
    dump_firewall(tf_dirs)
    dump_vpes(tf_dirs)


def dump_all(tf_dirs):
  table = rich.table.Table(title="tf dir outputs?")
  table.add_column("dir", justify="right", no_wrap=True)
  table.add_column("output?", justify="left", no_wrap=True)
  for tf_dir, outputs in tf_dirs.tf_dir_outputs.items():
      print(f'{tf_dir}:')
      for key, value in outputs.items():
        print(f'{key}: ', end="")
        print(outputs)
      table.add_row(tf_dir, str(len(outputs) != 0))
  print(table)

def dump():
    tf_dirs = TerraformOutput()
    if flag_all():
      dump_all(tf_dirs)
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
