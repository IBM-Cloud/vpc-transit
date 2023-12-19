#!/bin/bash

set -x

if [ $1 = create ]; then
  IBMCLOUD_IS_FEATURE_ADVERTISE_CUSTOM_ROUTES=true ibmcloud is vpc-routing-table-route-update \
    $vpc \
    $routing_table \
    $route \
    --advertise true
fi
