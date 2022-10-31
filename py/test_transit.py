import dump
import spur
import pytest
from dataclasses import dataclass
import shutil
import ipaddress
import re
import itertools


def username():
    return "root"


def curl_from_fip_to_ip_name(fip, ip):
    shell = spur.SshShell(
        hostname=fip,
        username=username(),
        missing_host_key=spur.ssh.MissingHostKey.accept,
    )
    with shell:
        try:
            result = shell.run(
                ["curl", "--connect-timeout", "2", f"{ip}/name"], allow_error=True
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


def curl_from_fip_to_ip_name_test_false(fip, ip, expected_result_str):
    assert False


def curl_from_fip_to_ip_name_test_true(fip, ip, expected_result_str):
    assert True


####################
class FromDict:
    def __init__(self, **entries):
        self.__dict__.update(entries)

class VPC(FromDict):
    pass


class Instance(FromDict):
    pass


@dataclass
class Curl:
    source: VPC
    destination: VPC

    def __str__(self):
        src = f"{self.source.name} ({self.source.fip}) {self.source.primary_ipv4_address}"
        dst = f"{self.destination.name} {self.destination.primary_ipv4_address}"
        return f"{src:50} -> {dst}"

    def test_me(self):
        curl_from_fip_to_ip_name_test(
            self.source.fip,
            self.destination.primary_ipv4_address,
            self.destination.name,
        )
        # curl_from_fip_to_ip_name_test_false(self.source.fip, self.destination.primary_ipv4_address, self.destination.name)


@dataclass
class DNS:
    source: VPC
    destination: VPC

    def dns_name(self, instance):
        name = instance.name
        zone = f"{name[:-6]}.com"  # instance name is prefix_transit-z0-s0 for zone and subnet the zone is prefix_transit.com
        return f"{name}.{zone}"

    def __str__(self):
        src = f"{self.source.name} ({self.source.fip}) {self.source.primary_ipv4_address}"
        dst = f"{self.destination.name} {self.destination.primary_ipv4_address}"
        return f"{src:50} -> {dst}"

    def test_me(self):
        curl_from_fip_to_ip_name_test(
            self.source.fip, self.dns_name(self.destination), self.destination.name
        )


def left_right_combinations(ret, left_instances, right_instances):
    for _, instance_left in left_instances.items():
        for _, instance_right in right_instances.items():
            ret.append((VPC(**instance_left), VPC(**instance_right)))


def instance_combinations():
    ret = []
    instances_enterprise = tf_dirs.test_instances_tf.enterprise["workers"]
    instances_transit = tf_dirs.test_instances_tf.transit["workers"]
    for left_right in [
        (instances_enterprise, instances_enterprise),
        (instances_transit, instances_transit),
        (instances_enterprise, instances_transit),
        (instances_transit, instances_enterprise),
    ]:
        left_right_combinations(ret, left_right[0], left_right[1])
    for spoke_number, vpc_spoke in tf_dirs.test_instances_tf.spokes.items():
        for instances in (instances_enterprise, instances_transit):
            left_right_combinations(ret, instances, vpc_spoke["workers"])
            left_right_combinations(ret, vpc_spoke["workers"], instances)
        for other_vpc_spoke_number, other_vpc_spoke in tf_dirs.test_instances_tf.spokes.items():
            left_right_combinations(
                ret, vpc_spoke["workers"], other_vpc_spoke["workers"]
            )
    return ret

def add_curl_to_test_dns(curls):
    ic = instance_combinations()
    for left, right in instance_combinations():
        curls.append(DNS(left, right))

def add_curl_connectivity_tests(curls):
    ic = instance_combinations()
    for left, right in instance_combinations():
        curls.append(Curl(left, right))

def add_vpc_instances_both_ways(ret, vpc_left, vpc_right):
    """Test left to right and right to left connectivity.  ssh using the vpc fip the curl the other private ip curl ip/name.
    There is an app that will return the name of the instance"""
    if vpc_left and vpc_right:
        instances_left = [instance for key, instance in vpc_left["instances"].items()]
        instances_right = [instance for key, instance in vpc_right["instances"].items()]
        for left in instances_left:
            for right in instances_right:
                # both ways
                for instance_left, instance_right in [(left, right), (right, left)]:
                    ret.append(Curl(VPC(**instance_left), VPC(**instance_right)))


def add_curl_connectivity_tests_1(ret):
    add_vpc_instances_both_ways(ret, tf_dirs.enterprise_tf.vpc, tf_dirs.transit_tf.vpc)
    for vpc_spoke in tf_dirs.spokes_tf.vpcs:
        add_vpc_instances_both_ways(ret, tf_dirs.enterprise_tf.vpc, vpc_spoke)
        add_vpc_instances_both_ways(ret, tf_dirs.transit_tf.vpc, vpc_spoke)
    # add spokes
    for left, right in itertools.combinations(tf_dirs.spokes_tf.vpcs, 2):
        add_vpc_instances_both_ways(ret, tf_dirs.enterprise_tf.vpc, vpc_spoke)

def parameters_for_test_curl():
    curls = list()
    add_curl_connectivity_tests(curls)
    return [pytest.param(curl, id=str(curl)) for curl in curls]

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
        src = f"{self.source_instance.name} ({self.source_instance.fip})) {self.source_instance.primary_ipv4_address}"
        dst =  f"{self.destination_vpc.name} ({str(self.destination_cidrs())}) {self.hostname()}"
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


def add_vpe_types(vpes, from_vpc, to_vpc, resources):
    """add all of the vpe types.  Each VPE dervied type is a different test: cos, redis, ..."""
    for _, instance_left in from_vpc["instances"].items():
        for resource in resources:
            vpes.append(
                vpe_type_to_class[resource["type"]](
                    "make_" + resource["type"],  # todo fix
                    Instance(**instance_left),
                    VPC(**to_vpc),
                    resource,
                )
            )


def collect_vpes():
    """create a vpe test objects for each vpe resources and source -> remote access combination
    vpe objects include cos, postgresql, redis, ...
    destinations are on the transit vpc and spoke vpcs
    sources are the enterprise -> transit, enterprise -> spokes, transit -> spokes"""
    vpes = list()
    vpe_transit_tf = tf_dirs.vpe_transit_tf
    if hasattr(vpe_transit_tf, "resources"):
        transit_resources = tf_dirs.vpe_transit_tf.resources
        # transit -> transit
        add_vpe_types( vpes, tf_dirs.transit_tf.vpc, tf_dirs.transit_tf.vpc, transit_resources)
        # enterprise -> transit
        add_vpe_types( vpes, tf_dirs.enterprise_tf.vpc, tf_dirs.transit_tf.vpc, transit_resources)
        for vpc_spoke in tf_dirs.spokes_tf.vpcs:
            # spoke -> enterprise
            add_vpe_types( vpes, vpc_spoke, tf_dirs.transit_tf.vpc, transit_resources)

        vpe_spokes_tf = tf_dirs.vpe_spokes_tf
        if hasattr(vpe_spokes_tf, "resources"):
            spoke_resources_all_spokes = vpe_spokes_tf.resources
            for key, vpc_spoke in enumerate(tf_dirs.spokes_tf.vpcs):
                spoke_resources = spoke_resources_all_spokes[str(key)]
                # spoke -> spoke
                add_vpe_types(vpes, vpc_spoke, vpc_spoke, spoke_resources)
                # transit -> spoke
                add_vpe_types( vpes, tf_dirs.transit_tf.vpc, vpc_spoke, spoke_resources)
                # enterprise -> spoke
                add_vpe_types( vpes, tf_dirs.enterprise_tf.vpc, vpc_spoke, spoke_resources,)
    return vpes


def collect_vpes_for_dns_testing():
    # return [pytest.param(vpe, id=str(vpe)) if vpe.can_test_vpe_dns_resolution() else pytest.param(vpe, id=str(vpe), marks=pytest.mark.skip) for vpe in collect_vpes()]
    vpes = collect_vpes()
    return [
        pytest.param(vpe, marks=vpe.test_vpe_dns_resolution_mark(), id=str(vpe))
        for vpe in vpes
    ]


def collect_vpes_for_resource_testing():
    return [
        pytest.param(vpe, marks=vpe.test_vpe_resource_mark(), id=str(vpe))
        for vpe in collect_vpes()
    ]


@pytest.mark.parametrize("curl", parameters_for_test_curl())
def test_curl(curl):
    curl.test_me()

@pytest.mark.parametrize("curl", parameters_for_test_curl_dns())
def test_curl_dns(curl):
    curl.test_me()

@pytest.mark.parametrize("vpe", collect_vpes_for_dns_testing())
def test_vpe_dns_resolution(vpe):
    vpe.test_vpe_dns_resolution()


@pytest.mark.parametrize("vpe", collect_vpes_for_resource_testing())
def test_vpe(vpe):
    vpe.test_vpe_resource()
