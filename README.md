# DISCLAIMER - WIP
WORK IN PROGRESS - not up to date with tutorial.......

# Transit VPC
The Virtual Private Cloud, VPC, is used to securely manage network traffic in the cloud.  VPCs can also be used as a way to encapsulate functionality.  The VPCs can be connected to each other using Transit Gateway.

A hub and spoke VPC model can serve a multitude of purposes.


![image](https://test.cloud.ibm.com/docs-content/v1/content/b1f2314e98e5628f204ce3619e53c3e87b196fda/solution-tutorials/images/vpc-transit-hidden/vpc-transit-overview.svg)

# TLDR;
Insure python virtual environment and terraform are available or docker as described in the prerequisite section below.  
Terraform and a python environment are required on your desktop development environment.  In the IBM Cloud you must [enable IP spoofing checks](https://{DomainName}/docs/vpc?topic=vpc-ip-spoofing-about#ip-spoofing-enable-check) and have a VPC ssh key.

```sh
git clone https://github.com/IBM-Cloud/vpc-transit
cd vpc-transit
cp config_tf/template.terraform.tfvars config_tf/terraform.tfvars
```

Make required changes to terraform.tfvars

```sh
edit config_tf/terraform.tfvars
```

Terraform will use your API key:
```sh
export IBMCLOUD_API_KEY=YourAPIKEy
```

Apply the layers described in the tutorial.  First get a list of the layers:
```sh
apply -p
```

Apply the layers.  Follow along in the tutorial to understand what each layer is accomplishing.  Or just install them all:

```sh
apply -p : :
```

Then test the results.  It is expected that some tests will fail.  See the tutorial for details:

```sh
pytest -m curl
```

See more details on pytest below.


# Prerequisites

Terraform and a python environment are required on your desktop development environment.

In the IBM Cloud the firewall-router instance will [allow_ip_spoofing](https://{DomainName}/docs/vpc?topic=vpc-ip-spoofing-about).  You must [enable IP spoofing checks](https://{DomainName}/docs/vpc?topic=vpc-ip-spoofing-about#ip-spoofing-enable-check).  You need an SSH key to connect to the virtual servers. If you don't have an SSH key, see [the instructions](/docs/vpc?topic=vpc-ssh-keys) for creating a key for VPC. 

## Docker image
A docker image can be created based on the [python image](https://hub.docker.com/_/python) and the [terraform linux Ubuntu/Debian install instructions](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

- Build docker image:
```sh
cd docker
docker build -t tools:latest .
cd ..
```

- Run docker image to make a container.  All steps in the tutorial will run the `./apply.sh` command and the `pytest` command will be done at the bash prompt provided by this command:
```
docker run -it --rm -v ~/.ssh:/root/.ssh -v `pwd`:/usr/src/app  -w /usr/src/app tools bash
```

## Python prerequisite
Python is used for testing.  You can skip the testing steps and trust the pass/fail results described in the tutorial.

You can use the docker image described above.

Or use a local version of python.

- Check version of python3 and verify it is 3.6.8 or later:
```
python --version
```
- If you have an old version of python you must install a newer version.  One way is to use [pyenv](https://github.com/pyenv/pyenv) to install the latest version of python.
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
- Install the required python libraries into the virtual environment:
```sh
pip install -r requirements.txt
```

## Terraform
Use the docker image described above.

Or find instructions to download and install terraform in the [Getting started with tutorials](https://{DomainName}/docs/solution-tutorials?topic=solution-tutorials-tutorials) guide.


# Pytest
## Pytest marks and filtering
The python test suite is in py/test_transit.py pytest.  There is some configuration in [pytest.ini](pytest.ini).

The default ssh environment is used to log into the test instances.  If you do not keep your ssh private key in the default location (~/.ssh/id_rsa for a mac or linux, ~/ssh/id_rsa for windows) the test suite will not work.

Each test will ssh to a VSI and then perform some kind of test: curl, ping, ... to a remote instance. The pytest.ini has marks for each class of tests:
- ping: ping test
- curl: curl test
- dns: dns test
- vpe: vpe test
- vpedns: vpedns test
- lb: loadbalancer test

There is also a mark for each zone for the `left` which is the VSI that is the ssh target and the `right` which is the remote VSI or VPE that is being tested:
- lz1: left zone1 test
- lz2: left zone2 test
- lz3: left zone3 test
- rz1: right zone1 test
- rz2: right zone2 test
- rz3: right zone3 test

The --co, collect only, can also be specified to see the tests that will be run.  Remove the --co flag to collect and then run the tests.  For example see the curl tests on zone 1 accessing only targets in zone 1:

```sh
pytest -m 'lz1 and rz1' --co
```

Try some other combinations:

```sh
pytest -m 'curl and lz1 and rz2' --co
```

You can also use the -k flag to filter the collection even more.  For example if you want to collect only the curl test from (enterprise zone 1) -> (spoke0 zone 1):

```sh
pytest -m 'curl' -k 'l-enterprise-z1 and r-spoke0-z1'  --co
```

## Pytest troubleshooting
If you find an unexpected failure use the TEST_DEBUG=1 environment variable to get more verbose output:

```sh
TEST_DEBUG=1 pytest -m 'curl' -k 'l-enterprise-z1 and r-spoke0-z1'  --co
```

Here is an example:
```
root@ac4518168076:/usr/src/app# TEST_DEBUG=1 pytest -m 'curl' -k 'l-enterprise-z1 and r-spoke0-z1'  --co
================================================================= test session starts ==================================================================
platform linux -- Python 3.11.1, pytest-7.2.1, pluggy-1.0.0 -- /usr/local/bin/python
cachedir: .pytest_cache
rootdir: /usr/src/app, configfile: pytest.ini, testpaths: py
collected 292 items / 291 deselected / 1 selected

<Module py/test_transit.py>
  <Function test_curl[l-enterprise-z1 (150.240.64.113) 192.168.0.4       -> 10.1.1.4 (52.116.134.171) r-spoke0-z1]>

=================================================== 1/292 tests collected (291 deselected) in 0.30s ====================================================
```
Notes:
- 150.240.64.113 - Floating IP address of the target VSI (left).  You can ssh to this VSI to reproduce the results by hand.
- 192.168.0.4 - Local IP address of the target VSI. 
- 52.116.134.171 - Floating IP address of the remote VSI.  Not used in the test.  You can also ssh to this VSI and run `tcpdump` to troubleshoot
- 10.1.1.4 - Local IP address of the remote VSI.

A heavily filtered example.  Reproduce the test result in the first shell:

```
$ ssh root@150.240.64.113
...
root@x-enterprise-z1-s0:~# hostname -I
192.168.0.4
root@x-enterprise-z1-s0:~# curl 10.1.1.4
...
```

Listen to tcpdump in a second shell:

```
$ ssh root@52.116.134.171

```


