# DISCLAMER - WIP
WORK IN PROGRESS - not up to date with tutorial.......

# Transit VPC
The Virtual Private Cloud, VPC, is used to securely manage network traffic in the cloud.  VPCs can also be used as a way to encapsulate functionality.  The VPCs can be connected to each other using Transit Gateway.

A hub and spoke VPC model can serve a multitude of purposes.


![image](https://test.cloud.ibm.com/docs-content/v1/content/b1f2314e98e5628f204ce3619e53c3e87b196fda/solution-tutorials/images/vpc-transit-hidden/vpc-transit-overview.svg)

# TLDR;
Insure python virtual environment and terraform are available or docker as described in the prerequisite section below:

```sh
git clone https://github.com/IBM-Cloud/vpc-transit
cd vpc-transit
cp config_tf/template.terraform.tfvars config_tf/terraform.tfvars
```

Make required changes to terraform.tfvars

```sh
edit config_tf/terraform.tfvars
```

Apply the layers described in the tutorial.  First get a list of the layers:
```sh
apply -p
```

Then apply them sequentially.  For example install VPCs, test instances and connectivity between VPCs:

```sh
apply -p : enterprise_link_tf
```

# Prerequisites

Terraform and a python environment are required.

## Docker image
A docker image can be created based on the [python image](https://hub.docker.com/_/python) and the [terraform linux Ubuntu/Debian install instructions](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)


```sh
cd docker
docker build -t tools:latest .
cd ..
docker run -it --rm -v ~/.ssh:/root/.ssh -v `pwd`:/usr/src/app  -w /usr/src/app python:3.11 bash
```

## Python prerequisite
Python is used for testing.  You can skip the testing steps and trust the pass/fail results described in the tutorial.

Use the docker image described above.

Or use a local version of python.  It is best to use one of the multitude of different ways to install python.  For example:

- Check version of python3 and verify it is 3.6.8 or later:
```
python --version
```
- If you have an old version of python use [pyenv](https://github.com/pyenv/pyenv) to install the latest
- In the directory of the cloned repository create a fresh python virtual environment to persist the required libraries:
```
python3 -m venv venv --prompt transit_vpc
```
- Activate the virtual environment.  This will need to be done each time a new terminal shell is initialized.  Mac or Linux:
```sh
source venv/bin/activate
```

Windows:
```sh
source venv/Scripts/activate
```

- Upgrade to the latest version of pip.
```sh
pip install --upgrade pip
```

## Terraform
Find instructions to download and install terraform in the [Getting started with tutorials](https://{DomainName}/docs/solution-tutorials?topic=solution-tutorials-tutorials) guide.

# Backup
Possible use cases for hub and spoke:
- The hub can be the respository for shared microservices
- The hub can be the repository for shared cloud resources, like databases, shared by the spokes over private endpoint gateways
- The hub can be a central point of traffic between on premises and the cloud.
- Enterprise traffic can be monitored, logged and routed through a Virtual Network Function, VNF, appliance in the hub
- The hub can can monitor cloud traffic
- The hub can hold the VPN resources that are shared by the spokes.

This solution tutorial will walk through communication paths in a hub and spoke VPC model.  It is typical for an organization to use a subset of the possible paths.  During the journey we will explore:
- VPC egress and ingress routing
- Virtual private endpoint gateways
- Transit Gateway
- DNS resolution
- Virtual Network Functions with optional Network Load Balancers to support high availability

A layered architecture will introduce resources and allow connectivity to be provided.  Each layer will add connectivity. The layers are implemented in terraform. It will be possible to change parameters, like number of zones, by changing a terraform variable.

## Configuration - config_tf
The configuration is a common place to capture parameters and some constants that will be used by all the layers.  You must edit the terraform.tfvars file and change at least a few of the configuration parameters.  In this first pass save yourself some time by specifying one spoke and one zone.

In addition an environment variable with your api key must be set in the shell:

```
vi config_tf/terraform.tfvars
export TF_VAR_ibmcloud_api_key=YOURKEY
```

Any time that you change config_tf/terraform.tfvars you will need to execute `terraform apply` in the config_tf directory.  It is then safest to sequentially execute all of the layers.

## Layers in Terraform
Each layer is implemented in a terraform directory with the suffix _tf.  The layers must be executed in order.  A layer later in the ordered list may acces outputs from previous layers.  A command `apply.sh` is available to help execute the layers in order.  To print the layers use the -p switch:

```
$ ./apply.sh -p
directories: config_tf enterprise_tf transit_tf spokes_tf transit_spoke_tgw_tf enterprise_link_tf firewall_tf transit_ingress_tf dns_tf vpe_transit_tf vpe_spokes_tf
>>> success
```

Try `./apply.sh -h` for help.  Execute `./apply.sh` with no parameters to apply to all layers.  The tutorial will walk you through the steps more slowly.

# s1 - Resource layers
This step will create the static resources in the picture above.  The VPCs for the hub and spoke are layed out similarly so a common VPC terraform modue is used. It contains a worker VSI in a worker subnet. A subnet for Private Endpoint Gateways and some other subnets required for future layers is are created.

- enterprise_tf - enterprise simulation layer
- transit_tf - transit (hub) vpc
- spokes_tf - all of the spokes

The following command will apply the layers:

```
./apply.sh spokes_tf
```

Once complete it is possible to test the connectivity.  There is a python pytest script that tests connectivity combinations.  I am using python 3.10.7.  I install and activate a virtual environment using the following steps.

```
python -m venv venv --prompt transit_vpc
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

Now (and each time a fresh shell is initialized) remember to activate the python virtual environment:
```
source venv/bin/activate
```

Run the tests:

```
TEST_DEBUG=1 pytest -v
```

Ignoring the details the final line indicates that **all** tests are failing:

```
$ pytest -v
...
=== 60 failed, 2 skipped in 144.12s (0:02:24) ==
```

# s? - Transit to Spokes Transit Gateway
The layer `transit_spoke_tgw_tf` will create a regional Transit Gateway.  The transit VPC and all of the spoke VPCs will be connected.

```
./apply.sh transit_spoke_tgw_tf
```


Test:
```
$ pytest -v
...
```
You will notice that the tranit <-> spoke communication tests are passing.  The enterprise <-> spoke communications are failing as well as the DNS tests.

```
# pytest -v
...
```

# s? - Direct Link
The enterprise tests are failing because there is no data path enterprise <-> transit.  Later VPN will be simulated but for now a simulation of direct link will be established using the Transit Gateway service.

Verify that config_tf/terraform.tfvars has `vpn = false` set.

```
./apply.sh enterprise_link_tf
```

Test:
```
$ pytest -v
...
```
This fixed some of the enterprise <-> transit failures.  This did not fix any of the enterprise <-> spoke failures.  It is not possible to route traffic through a VPC without passing through a network interface.  There is actually little value in passing through the transit unless you wish to monitor, filter, report, ...  If this is not required, connect the enterprise directly to the spokes. 

![image](https://media.github.ibm.com/user/1667/files/f978bb00-49e9-11ed-8c0f-3418cb4905c1)

# s? - Router (firewall, traffic filter, monitor, ...)
Since the incentive for a transit vpc from the enterprise is to have a central place to monitor, inspect, route and log traffic.  A firewall/routing appliance can be installed in the transit VPC. 

An off the shelf appliance can be used for a router.  There are many to choose from in the IBM Catalog.  A subnet has been created in each of the zones of the transit to hold the firewall.  It will be required to configure a firewall instance with `allow_ip_spoofing`.  This will require some additional privileges even if you are the account administrator.  TODO ADD LINK TO INSTRUCTIONS FOR SPOOFING.  See [Private hub and spoke with transparent VNF and spoke-to-spoke traffic Figure](https://cloud.ibm.com/docs/vpc?topic=vpc-about-vnf-ha) for some additional information.

In this example the firewall instance is implemented by Ubuntu with routing enabled.  It will take all packets with destination IP addresses not for itself and forward them unchanged.

```
./apply.sh firewall_tf
```

Test:
```
$ pytest -v
...
```

## Routing
The firewall needs to be in the middle of all traffic enterprise <-> spoke.  This is acheived by adding routes to the vpc ingress routing table.  The following fields in a route are of interest:

zone - The zone in the transit VPC.
destination - CIDR block containing the IP address of the destination
next_hop - firewall running in the zone

Each network packet 



## Note - Transit VPC Address Prefixes

The simulated 

Q: How does tr

## Note - Asymmetric routing
Notice that the the enterprise <-> spoke across zones is not working.  This is due to the asymmetric routing path that has been introduced.  VPC routing uses stateful VPC routing for level 3 traffic.  A tcp connection is established internally through a route during the connection and must be replicated on the return path.  An example of the issue is shown in the diagram below.

![image](https://media.github.ibm.com/user/1667/files/7951ca00-4eaf-11ed-9d70-3b36d7e6b8d1)

The green arrows indicate success.  The asymmetric route is introduced starting with the blue arrow.  The enterprise server 192.168.1.4 is associated to the lower zone in transit VPC as selected by the address prefix 192.168.1.0/24 .  When connecting to 10.0.1.4 Transit Gateway chooses the upper zone based on the Address Prefix 10.0.1.0/24.  Ingress routing in the transit VPC selects the Firewall VSI (10.0.0.196) in the zone and establishes a L3 stateful tcp route for 192.168.1.4 -> 10.0.1.4 through 10.0.0.196

On the return trip the reply from the spoke to 10.0.1.4 -> 192.168.1.4 the Transit Gateway chooses the lower zone based on the address prefix 192.168.1.0/24 and the associated Firewall VSI 10.1.0.196.  This does not follow the initial tcp route established earlier and is dropped before being delivered to the firewall.

Ping traffic is L2 and does not establish a stateful L3 route.  These will be routed enterprise <-> spoke.

## Network Load Balancer
Optionally a Highly Available, HA, firewall can be created by using a Network Load Balancer in "route" mode.  This will distribute traffic over the pool members.  The config_tf/terraform.tfvars has the settings that control the firewall.

- firewall - set to true to create a firewall
- firewall_nlb  set to true to create a load balancer in route mode
- number_of_firewalls_per_zone - specify a small integer indicating the number of load balancer pool members

If you wish to configure this make these changes in the tfvars file and run ./apply.sh again.  This is a transparent chnge that does not effect the test results.

# s? - DNS
Introducing DNS will allow more of the tests to pass.  If it is possible use a single DNS service for the the cloud (transit and spokes).  This section assumes that there is a seperate DNS service for each VPC (each team).  The independence will allow more isolation between the teams and it will allow us to more easily move to a multi-account architecture in the future.  This diagram explains the configuration:

![image](https://media.github.ibm.com/user/1667/files/b7537780-49f1-11ed-943e-32e667cbedb9)

A IBM DNS service has resolver locations.  These are appliances that are added to VPC subnets.  This scenario requires the following resolver location functionality

- IP addresses the can be used to resolve the DNS names stored in the VPC.  In the diagram the arrows point to the IP addresses of the resolvers
- Forwarding rules provide a table that maps DNS Zones to IP addresses of resolvers that will provide the name resolution for the DNS zone.  The tables are shown attached to the arrows.

The arrows and associated tables seem intuitive.  In order for the enterprise to get to `m0.transit.com` it will need to ask the transit DNS resolver.  In order for a spoke to resolve `m1.enterprise.com` it trusts transit, which will in turn forwards the request to the enterprise.

Try `pytest -v` and notice a lot of stuff is working.  Only the enterprise <--> spoke paths are failing.

```
./apply.sh dns_tf
pytest -v
```

Now all the tests should be passing except the cross zone enterprise <-> spoke impacted by asymmetric routing.

# s? - Spoke Egress Routing

If your set up requires cross zone enterprise <-> spoke routing than egress routing in the spoke VPCs can be used. Add a route for each zone in the spoke with a destination of the enterprise 192.168.0.0/16 and specify a next_hop of the firewall in the same zone 10.0.0.196.  This makes the route symmetric since the return trip from spoke -> enterprise returns through the same path as the initial enterprise -> spoke L3 connection request.

```
./apply.sh spoke_egress_tf
pytest -v
```

All tests are passing.  But some VPE tests got skipped.

# s? - Virtual Private Endpoint Gateway
Virtual Private Endpoint Gateways provides private connectivity to IBM services within the VPC.  This example uses the IBM Cloud Database for REDIS.  Verify that config_tf/terraform.tfvars has `make_redis = true` set.  Create the database instance in the transit VPC:

```
./apply.sh vpe_transit_tf
pytest -v
```

Notice the `test_vpe_dns_resolution` and `test_vpe` tests.

test_vpe_dns_resolution - Verifies that the DNS resolution of the database is in the private CIDR block of the VPC.  This insures that the VPE is being used to access the cloud resources.

test_vpe - Verifies that the cloud resources can be accessed.

Notice that the tests are 


- vpe_transit_tf - vpe for transit
- vpe_spokes_tf - vpe for spokes


# s? - VPN

The enterperise can be connected to the cloud using VPN.  Remember that the enterprise VPC is simulating a remote data center. It is not recommended to use VPN to connect two IBM VPCs.  Spoiler alert we are a few steps away of simulating direct connect as an alternative to VPN. 

# Miscellaneous

You can optionally save some disk space by sharing terraform plugins across the layers using a [config-file](https://developer.hashicorp.com/terraform/cli/config/config-file).  On linux:

$HOME/.terraformrc:

   ```sh
   plugin_cache_dir   = "$HOME/.terraform.d/plugin-cache"
   disable_checkpoint = true
   ```
   {: codeblock}

To avoid the installation of these tools you can use the [{{site.data.keyword.cloud-shell_short}}](https://{DomainName}/shell) from the {{site.data.keyword.cloud_notm}} console, but be aware that restarting the shell results in the loss of disk with associated terraform state files and environment.  It will be required to complete the tutorial and remove resources in one session.  Use the terraform plugin cache to avoid reaching the 500MB limit.