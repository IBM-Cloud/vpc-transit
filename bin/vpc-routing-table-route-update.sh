#!/bin/bash

set -x

if [ $1 = create ]; then
  ibmcloud login --apikey $IBMCLOUD_API_KEY
  ibmcloud target -r $region
  IBMCLOUD_IS_FEATURE_ADVERTISE_CUSTOM_ROUTES=true ibmcloud is vpc-routing-table-route-update \
    $vpc \
    $routing_table \
    $route \
    --advertise true
fi
