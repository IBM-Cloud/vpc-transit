#!/bin/bash

set -x

if [ $1 = create ]; then
  IBMCLOUD_IS_FEATURE_ADVERTISE_CUSTOM_ROUTES=true ibmcloud is vpc-routing-table-update \
    $vpc \
    $routing_table \
    --advertise-routes-to transit_gateway \
    --transit-gateway-ingress true
fi
