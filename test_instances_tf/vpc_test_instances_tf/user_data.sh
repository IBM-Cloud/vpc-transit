#!/bin/bash
set -x

# See substitution in terraform
NAME=__NAME__

# spoke test instances need to wait for transit gateway spoke -> transit connectivity for DNS resolution
while ! apt-get update; do sleep 60; done
apt-get install -y nginx net-tools ntpdate ntp postgresql-client-common postgresql-client
ifconfig ens3 mtu 1200;# see https://jiracloud.swg.usma.ibm.com:8443/browse/VPN-365
echo $NAME > /var/www/html/name
curl localhost/name
# ibmcloud
curl -fsSL https://clis.cloud.ibm.com/install/linux | sh
