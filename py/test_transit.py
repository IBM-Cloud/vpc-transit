import dump
import spur
import pytest
from dataclasses import dataclass
import shutil
import ipaddress
import re
import itertools
import os


def username():
    return "root"


def verbose_output() -> bool:
  env_var = "TEST_DEBUG"
  return env_var in os.environ

def curl_from_fip_to_ip_name(fip, ip):
    shell = spur.SshShell(
        hostname=fip,
        username=username(),
        missing_host_key=spur.ssh.MissingHostKey.accept,
    )
    with shell:
        try:
            result = shell.run(
                ["curl", "--max-time", "4", f"{ip}/name"], allow_error=True
            )
            if result.return_code == 0:
                return (True, result.output.decode("utf-8").strip(), result)
            else:
                return (
                    False,
                    f'output: {result.output.decode("utf-8")} error: {result.stderr_output.decode("utf-8")}',
                    result,
                )
        except spur.ssh.ConnectionError:
            return (False, f"connection error fip:{fip}, ip:{ip}", None)


def curl_from_fip_to_ip_name_test(fip, ip, expected_result_str):
    (success, return_str, result) = curl_from_fip_to_ip_name(fip, ip)
    print(return_str)
    assert success
    assert return_str == expected_result_str

def ping_from_fip_to_ip_name(fip, ip):
    shell = spur.SshShell(
        hostname=fip,
        username=username(),
        missing_host_key=spur.ssh.MissingHostKey.accept,
    )
    with shell:
        try:
            result = shell.run(
                ["ping", "-c", "2", f"{ip}"], allow_error=True
            )
            if result.return_code == 0:
                return (True, result.output.decode("utf-8").strip(), result)
            else:
                return (
                    False,
                    f'output: {result.output.decode("utf-8")} error: {result.stderr_output.decode("utf-8")}',
                    result,
                )
        except spur.ssh.ConnectionError:
            return (False, f"ping error fip:{fip}, ip:{ip}", None)


def ping_from_fip_to_ip_name_test(fip, ip, expected_result_str):
    (success, return_str, result) = ping_from_fip_to_ip_name(fip, ip)
    print(return_str)
    assert success

def basic_name(name: str):
    "basic name takes a tvpc-spoke1-z1-s0 and removes the basename to return spoke1-z1-s0"
    basename = tf_dirs.config_tf.settings["basename"]
    return name[len(basename) + 1:]

@dataclass
class VPC:
  name: str
  zones: [str]

@dataclass
class Instance:
  fip: str
  id: str
  name: str
  primary_ipv4_address: str
  subnet_name: str
  zone: str

@dataclass
class ToFrom:
    source: Instance
    destination: Instance
    def __str__(self):
        if verbose_output():
          src = f"l-{basic_name(self.source.name)} ({self.source.fip}) {self.source.primary_ipv4_address}"
          dst = f"{self.destination.primary_ipv4_address} ({self.destination.fip}) r-{basic_name(self.destination.name)}"
          return f"{src:50} -> {dst}"
        else:
          src = f"l-{basic_name(self.source.name)}"
          dst = f"r-{basic_name(self.destination.name)}"
          return f"{src:15} -> {dst}"


@dataclass
class Curl(ToFrom):
    def test_me(self):
        curl_from_fip_to_ip_name_test(
            self.source.fip,
            self.destination.primary_ipv4_address,
            self.destination.name,
        )

    def ping_me(self):
        ping_from_fip_to_ip_name_test(
            self.source.fip,
            self.destination.primary_ipv4_address,
            self.destination.name,
        )

@dataclass
class DNS(ToFrom):
    def dns_name(self, instance):
        name = instance.name
        zone = f"{name[:-6]}.com"  # instance name is prefix_transit-z0-s0 for zone and subnet the zone is prefix_transit.com
        return f"{name}.{zone}"

    def test_me(self):
        curl_from_fip_to_ip_name_test(
            self.source.fip, self.dns_name(self.destination), self.destination.name
        )


def left_right_combinations(ret, left_instances, right_instances):
    for _, instance_left in left_instances.items():
        for _, instance_right in right_instances.items():
            ret.append((Instance(**instance_left), Instance(**instance_right)))


def all_instances():
    workers = [*tf_dirs.test_instances_tf.enterprise["workers"].values(), *tf_dirs.test_instances_tf.transit["workers"].values()] + [worker for spoke in tf_dirs.test_instances_tf.spokes.values() for worker in spoke["workers"].values()]
    return [Instance(**worker) for worker in workers]

def instance_combinations():
    instances = all_instances()
    return itertools.product(instances, instances)

def add_curl_to_test_dns(curls):
    for left, right in instance_combinations():
        curls.append(DNS(left, right))

def add_curl_connectivity_tests(curls):
    for left, right in instance_combinations():
        curls.append(Curl(left, right))

def zoneid(instance: Instance):
  if instance.zone.find("-1") >= 0:
    return 0
  if instance.zone.find("-2") >= 0:
    return 1
  if instance.zone.find("-3") >= 0:
    return 2
  raise Exception("bad zone")

def marks_find(first_mark, curl: Curl) -> [pytest.mark]:
  lz = [pytest.mark.lz0, pytest.mark.lz1, pytest.mark.lz2][zoneid(curl.source)]
  rz = [pytest.mark.rz0, pytest.mark.rz1, pytest.mark.rz2][zoneid(curl.destination)]
  return [first_mark, lz, rz]

def parameters_for_test_curl(first_mark):
    curls = list()
    add_curl_connectivity_tests(curls)
    return [pytest.param(curl, id=str(curl), marks=marks_find(first_mark, curl)) for curl in curls]

def parameters_for_test_curl_dns():
    try:
      # has dns been initialized?
      module_dns = tf_dirs.dns_tf.module_dns
    except: 
      return [ ]
    curls = list()
    add_curl_to_test_dns(curls)
    return [pytest.param(curl, id=str(curl)) for curl in curls]


tf_dirs = dump.TerraformOutput()


def command_on_fip(fip, command_as_list):
    execution_point = f"Open remote shell to fip {fip} username {username()} command {command_as_list}"
    shell = spur.SshShell(
        hostname=fip,
        username=username(),
        missing_host_key=spur.ssh.MissingHostKey.accept,
    )
    try:
        with shell:
            ret = run_remote_get_output(shell, command_as_list)
    except Exception as err:
        ret = ExecutionResult(exception=err, execution_point=execution_point)
    return ret


def run_remote_get_output(shell, command_as_list):
    try:
        result = shell.run(command_as_list, allow_error=True)
        ret = ExecutionResult(
            result.return_code,
            result.output.decode("utf-8"),
            result.stderr_output.decode("utf-8"),
        )
    except Exception as err:
        # ret = (False, f"connection error fip:{fip}, ip:{ip}", None)
        ret = ExecutionResult(exception=err)
    return ret


@dataclass
class ExecutionResult:
    """spur.ExecutionResult is not exported"""

    return_code: int = -1
    output: str = ""
    stderr_output: str = ""
    execution_point: str = ""
    exception: Exception = None

    def assert_for_test(self):
        if self.return_code == 0:
            print(self.output)
            return
        if self.execution_point:
            print(f"Execution point: {self.execution_point}")
        if self.exception:
            raise self.exception
        print("--stderr_output--")
        print(self.stderr_output)
        print("--output--")
        print(self.output)
        assert False


# 7bc1ddc3-f74b-4ead-af91-c9a14df3f71e.bkvfu0nd0m8k95k94ujg.private.databases.appdomain.cloud has address 192.168.16.8
# *? - not greedy, find the first occurance of ' has address '
# (?s) - . matches new lines
re_host_command_has_address = re.compile(r"(?s).*? has address ([0-9\.]+)")


def fip_resolves_hostname(fip, dns_name):
    """ssh to fip and resolve the hostname"""
    ret = command_on_fip(fip, ["systemd-resolve", "--flush-caches"])
    ret.assert_for_test()
    ret = command_on_fip(fip, ["host", dns_name])
    ret.assert_for_test()
    global re_host_command_has_address
    m = re_host_command_has_address.match(ret.output)
    assert m
    ip_string = m.group(1)
    return ip_string


def ip_in_cidrs(ip_string, cidr_strings):
    ip = ipaddress.ip_address(ip_string)
    for cidr_string in cidr_strings:
        cidr = ipaddress.ip_network(cidr_string)
        if ip in cidr:
            return True
    return False


def dns_from_fip_to_name_test(hostname, fip, cidr_strings):
    """verify that in the context of the fip that the dns address resolved for the name
    is in the cidrs"""
    ip_string = fip_resolves_hostname(fip, hostname)
    assert ip_in_cidrs(
        ip_string, cidr_strings
    ), f"{ip_string} not in {cidr_strings} from {hostname}"


def vpe_redis_test(fip, resource):
    """execute a command in fip to verify postgresql is accessible"""
    redis = resource["key"]
    credentials = redis["credentials"]
    cert_data = credentials["connection.rediss.certificate.certificate_base64"]
    cli_arguments = credentials["connection.cli.arguments.0.1"]
    command = f""" 
#!/bin/bash
set -ex
if [ -x ./redli ]; then
  echo redli already installed
else
  curl -LO https://github.com/IBM-Cloud/redli/releases/download/v0.5.2/redli_0.5.2_linux_amd64.tar.gz
  tar zxvf redli_*_linux_amd64.tar.gz
fi

./redli \
  --long \
  -u {cli_arguments} \
  --certb64={cert_data} << TEST > redis.out
  set foo working
  get foo
  del foo
TEST
# show the redis output
cat redis.out
# look for the value of the key in the output
cat redis.out | grep working
""".lstrip()
    shell_command_on_fip(fip, command)


def vpe_postgresql_test(fip, resource):
    """execute a command in fip to verify postgresql is accessible"""
    postgresql = resource["key"]
    credentials = postgresql["credentials"]
    cert_data = credentials["connection.postgres.certificate.certificate_base64"]
    pgpassword = credentials["connection.postgres.authentication.password"]
    postgresql_username = credentials["connection.postgres.authentication.username"]
    cli_arguments = credentials["connection.cli.arguments.0.0"]
    pgsslrootcert = credentials["connection.cli.environment.PGSSLROOTCERT"]
    command = f""" 
#!/bin/bash
set -ex
echo "{cert_data}" | base64 -d > {pgsslrootcert}
USERNAME={postgresql_username} \
PGPASSWORD={pgpassword} \
PGSSLROOTCERT={pgsslrootcert} \
    psql "{cli_arguments}" >psql.out <<PSQL
  SELECT 1;
PSQL
cat psql.out
# check the psql output for something reasonable
cat psql.out | grep '1 row'
""".lstrip()
    shell_command_on_fip(fip, command)


def shell_command_on_fip(fip, command):
    remote_file_name = "/t.sh"
    command_as_list = ["sh", "-c", f"chmod 755 {remote_file_name}; {remote_file_name}"]
    execution_point = f"Open remote shell to fip {fip} username {username()} command {command_as_list}"
    print(execution_point)
    shell = spur.SshShell(
        hostname=fip,
        username=username(),
        missing_host_key=spur.ssh.MissingHostKey.accept,
    )
    try:
        with shell.open(remote_file_name, "w") as remote_file:
            remote_file.write(command)
            remote_file.close()
            with shell:
                ret = run_remote_get_output(shell, command_as_list)
                # shell.run(["rm", remote_file_name]) # leave the example around for manual testing
    except Exception as err:
        ret = ExecutionResult(exception=err, execution_point=execution_point)
    ret.assert_for_test()


@dataclass
class VPE:
    """
    VPE connectivity test instance.  In the context of an a vpc_instance test the access to a vpe (vpc private endpoint gateway) resource.
    source_instance - provides a fip and an instance to run a test program
    destination_resource - ibm_resource_key created to access the resource, properties include dns name, username, password, ...
    destination_vpc - the vpe is in each of the subnets of this vpc
    """

    vpe_type: str
    source_instance: Instance
    destination_vpc: VPC
    destination_resource: dict

    def destination_cidrs(self):
        subnet_vpe = tf_dirs.config_tf.settings["subnet_vpe"]  # 2
        return [
            zone["subnets"][subnet_vpe]["ipv4_cidr_block"]
            for zone in self.destination_vpc.zones
        ]

    def __str__(self):
        src = f"{basic_name(self.source_instance.name)} ({self.source_instance.fip}) {self.source_instance.primary_ipv4_address}"
        dst =  f"{basic_name(self.destination_vpc.name)} ({str(self.destination_cidrs())}) {self.hostname()}"
        return f"{self.vpe_type[5:]} {src} -> {dst}"

    def test_vpe_dns_resolution(self):
        dns_from_fip_to_name_test(
            self.hostname(), self.source_instance.fip, self.destination_cidrs()
        )

    def test_vpe_dns_resolution_mark(self):
        return list()

    def test_vpe_resource(self):
        assert Fail, "test_vpe_resource should be overridden todo"

    def test_vpe_resource_mark(self):
        return list()

    def from_not_spoke_too_spoke(self):
        instance_name = self.source_instance.name[-8:-3]
        vpc_name = self.destination_vpc.name[-7:-2]
        return instance_name != "spoke" and vpc_name == "spoke"


class VPE_POSTGRESQL(VPE):
    def hostname(self):
        postgresql = self.destination_resource["key"]
        credentials = postgresql["credentials"]
        return credentials["connection.postgres.hosts.0.hostname"]

    def test_vpe_resource_mark(self):
        # vpe is broken through transit gateway
        # [Virtual Private Endpoint (NG) - Rel 1.2 Connect to VPE enabled service in a multi-cloud enterprise. (i.e. DirectLink/TGW/VPN)](https://bigblue.aha.io/features/PRVEP-35)
        # if self.from_not_spoke_too_spoke():
        #    return pytest.mark.xfail
        return list()

    def test_vpe_resource(self):
        vpe_postgresql_test(self.source_instance.fip, self.destination_resource)


class VPE_REDIS(VPE):
    def hostname(self):
        redis = self.destination_resource["key"]
        credentials = redis["credentials"]
        return credentials["connection.rediss.hosts.0.hostname"]

    def test_vpe_resource_mark(self):
        # if self.from_not_spoke_too_spoke():
        #    return pytest.mark.xfail
        # todo list?
        return list()

    def test_vpe_resource(self):
        vpe_redis_test(self.source_instance.fip, self.destination_resource)


class VPE_COS(VPE):
    def hostname(self):
        return self.destination_resource["cos_endpoint"]

    def test_vpe_dns_resolution_mark(self):
        # the cos dns name is not unique.  It is always something like s3.direct.us-south.cloud-object-storage.appdomain.cloud
        # it will be resolved by transit and not by spoke - this is expected
        if self.from_not_spoke_too_spoke():
            return pytest.mark.skip
        return list()

    def test_vpe_resource_mark(self):
        # todo COS test has not been written yet
        return pytest.mark.skip

    def test_vpe_resource(self):
        assert False, "todo cos not implemented should be skipped"


vpe_type_to_class = {"cos": VPE_COS, "redis": VPE_REDIS, "postgresql": VPE_POSTGRESQL}


def add_vpe_types(vpes, from_test_instances, to_vpc, resources):
    """add all of the vpe types.  Each VPE dervied type is a different test: cos, redis, ..."""
    for instance_left in from_test_instances:
        for resource in resources:
            vpes.append(
                vpe_type_to_class[resource["type"]](
                    "make_" + resource["type"],  # todo fix
                    instance_left,
                    VPC(name=to_vpc["name"], zones=to_vpc["zones"]),
                    resource,
                )
            )


def collect_vpes():
    """create a vpe test objects for each vpe resources and source -> remote access combination
    vpe objects include cos, postgresql, redis, ...
    destinations are on the transit vpc and spoke vpcs
    sources are the enterprise -> transit, enterprise -> spokes, transit -> spokes"""
    vpes = list()
    instances = all_instances()
    vpe_transit_tf = tf_dirs.vpe_transit_tf
    if hasattr(vpe_transit_tf, "resources"):
        add_vpe_types( vpes, instances, tf_dirs.transit_tf.vpc, tf_dirs.vpe_transit_tf.resources)
        vpe_spokes_tf = tf_dirs.vpe_spokes_tf
        if hasattr(vpe_spokes_tf, "resources"):
            for spoke_number_str, spoke_resources in vpe_spokes_tf.resources.items():
                spoke_number = int(spoke_number_str)
                vpc_spoke = tf_dirs.spokes_tf.vpcs[spoke_number]
                add_vpe_types(vpes, instances, vpc_spoke, spoke_resources["resources"])
    return vpes


def collect_vpes_for_dns_testing():
    return [
        pytest.param(vpe, marks=vpe.test_vpe_dns_resolution_mark(), id=str(vpe))
        for vpe in collect_vpes()
    ]


def collect_vpes_for_resource_testing():
    return [
        pytest.param(vpe, marks=vpe.test_vpe_resource_mark(), id=str(vpe))
        for vpe in collect_vpes()
    ]

####
def curl_from_fip_to_lb_test(fip, ip):
    (success, return_str, result) = curl_from_fip_to_ip_name(fip, ip)
    print(return_str)
    assert success

@dataclass
class LB:
    hostname: str
    private_ips: [str]
    name: str

@dataclass
class LBTest:
    source: Instance
    destination: str # ip address of the LB
    lb: LB

    def __str__(self):
        src = f"{basic_name(self.source.name)} ({self.source.fip}) {self.source.primary_ipv4_address}"
        dst = f"{basic_name(self.lb.name)} {self.destination} {self.lb.hostname}"
        return f"{src:50} -> {dst}"

    def test_me(self):
        curl_from_fip_to_lb_test(
            self.source.fip,
            self.destination,
        )

def add_lb_types1(tests, instances_list_of_list, lb):
  for source_lists in instances_list_of_list:
    for key, source in source_lists.items():
      for private_ip in lb.private_ips:
        tests.append(LBTest(Instance(**source), private_ip, lb))

def collect_lb_tests1():
    """create load balancer test objects for each test_instance -> load_balancer access combination
    The list of load balancers are in the test_lb_tf directory
    sources are the enterprise, transit and spokes"""
    ret = list()
    instances_enterprise = tf_dirs.test_instances_tf.enterprise["workers"]
    instances_transit = tf_dirs.test_instances_tf.transit["workers"]
    instances_spokes = [spoke_test_instances["workers"] for spoke_test_instances in tf_dirs.test_instances_tf.spokes.values()]
    instances_list_of_list = [instances_enterprise, instances_transit] + instances_spokes
    try:
      # has test_lbs_tf been initialized?
      lbs = tf_dirs.test_lbs_tf.lbs
    except: 
      return [ ]
    for lbmodule_number, lbmodule in lbs.items():
      lb_input = lbmodule["lb"]
      lb = LB(hostname=lb_input["hostname"], private_ips=lb_input["private_ips"], name=lb_input["name"])
      add_lb_types(ret, instances_list_of_list, lb)
    return ret

def add_lb_types(tests, instances, lb):
  for instance in instances:
    for private_ip in lb.private_ips:
      tests.append(LBTest(instance, private_ip, lb))

def collect_lb_tests():
    """create load balancer test objects for each test_instance -> load_balancer access combination
    The list of load balancers are in the test_lb_tf directory
    sources are the enterprise, transit and spokes"""
    ret = list()
    instances = all_instances()
    try:
      # has test_lbs_tf been initialized?
      lbs = tf_dirs.test_lbs_tf.lbs
    except: 
      return [ ]
    for lbmodule_number, lbmodule in lbs.items():
      lb_input = lbmodule["lb"]
      lb = LB(hostname=lb_input["hostname"], private_ips=lb_input["private_ips"], name=lb_input["name"])
      add_lb_types(ret, instances, lb)
    return ret


def collect_lbs_for_testing():
    lbs = collect_lb_tests()
    ret =  [
        pytest.param(lb, id=str(lb)) for lb in lbs
    ]
    return ret


@pytest.mark.parametrize("ping", parameters_for_test_curl(pytest.mark.ping))
def test_ping(ping):
    ping.ping_me()

@pytest.mark.parametrize("curl", parameters_for_test_curl(pytest.mark.curl))
def test_curl(curl):
    curl.test_me()

@pytest.mark.dns
@pytest.mark.parametrize("curl", parameters_for_test_curl_dns())
def test_curl_dns(curl):
    curl.test_me()

@pytest.mark.vpedns
@pytest.mark.parametrize("vpe", collect_vpes_for_dns_testing())
def test_vpe_dns_resolution(vpe):
    vpe.test_vpe_dns_resolution()

@pytest.mark.vpe
@pytest.mark.parametrize("vpe", collect_vpes_for_resource_testing())
def test_vpe(vpe):
    vpe.test_vpe_resource()

@pytest.mark.lb
@pytest.mark.parametrize("lb", collect_lbs_for_testing())
def test_lb(lb):
    lb.test_me()
