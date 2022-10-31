#!/bin/bash

# parameters via substitution done in terraform
NAME=__NAME__

apt-get update
apt-get install -y nginx ntpdate ntp postgresql-client-common postgresql-client
ifconfig ens3 mtu 1200;# see https://jiracloud.swg.usma.ibm.com:8443/browse/VPN-365
echo $NAME > /var/www/html/name
curl localhost/name
# ibmcloud
curl -fsSL https://clis.cloud.ibm.com/install/linux | sh
