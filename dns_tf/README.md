# dns support
Create a DNS instance for transit and enterprise.  Create an example zone and a dns record.
Terraform does have support for **resolver location** so the following needs to be done by hand for each instance (enterprise and transit):

```
for subnet in subnets:
  dns_instance_id=4634aa8e-8939-480d-815b-61e3c7c77c37
  crn=crn:v1:bluemix:public:is:us-south-1:a/713c783d9a507a53135fe6793c37cc74::subnet:0717-ccb09a83-4e0f-4d6a-8bb2-1ca76377e530
  name=enterprise
  locations="--location $crn $locations"

ibmcloud dns custom-resolver-create --name $name --instance $dns_instance_id $locations
resolver_id=?
wait for locations to be working
ibmcloud dns custom-resolver-update $dns_instance_id $resolver_id --enabled true
return the location_ips




delete
  resolver_id=42c32807-fd50-45df-8c52-a3a5c4c63f60
  ibmcloud dns custom-resolver-delete --force --instance $dns_instance_id $resolver_id

```
- create a custom resolver, with configuration:
- add resolver location subnet for each of the two subnets
- add forwarding rules for **other**.com to other_ip_1 and other_ip_2
- enterprise only: add postgres forwarding rules for serviceds, postgres: appdomain.cloud to other_ip_1 and other_ip_2

On delete
- disable custom resolver
- delete custom resolver

dns = {
  "enterprise" = {
    "dns_instance_id" = "4634aa8e-8939-480d-815b-61e3c7c77c37"
    "server_name" = "server.enterprise.com"
    "subnets" = {
      "0" = {
        "crn" = "crn:v1:bluemix:public:is:us-south-1:a/713c783d9a507a53135fe6793c37cc74::subnet:0717-ccb09a83-4e0f-4d6a-8bb2-1ca76377e530"
        "ipv4_cidr_block" = "192.168.128.0/20"
        "zone" = "us-south-1"
      }
      "1" = {
        "crn" = "crn:v1:bluemix:public:is:us-south-2:a/713c783d9a507a53135fe6793c37cc74::subnet:0727-0452f0f1-d524-46b9-a4c0-f0f91b41619c"
        "ipv4_cidr_block" = "192.168.144.0/20"
        "zone" = "us-south-2"
      }
    }
    "vpc_crn" = "crn:v1:bluemix:public:is:us-south:a/713c783d9a507a53135fe6793c37cc74::vpc:r006-d63abee1-f54a-4e0f-a65e-53882f8860e0"
    "zone_id" = "2c9332ba-616b-4348-b2c9-31d006e0c413"
  }
  "transit" = {
    "dns_instance_id" = "aae08759-8d89-42aa-a637-d15107ce3c6f"
    "server_name" = "server.transit.com"
    "subnets" = {
      "0" = {
        "crn" = "crn:v1:bluemix:public:is:us-south-1:a/713c783d9a507a53135fe6793c37cc74::subnet:0717-28e2a6a7-3ec4-40b6-a6e5-48623715f6cc"
        "ipv4_cidr_block" = "192.168.0.0/20"
        "zone" = "us-south-1"
      }
      "1" = {
        "crn" = "crn:v1:bluemix:public:is:us-south-2:a/713c783d9a507a53135fe6793c37cc74::subnet:0727-e3c196c7-f608-4771-933d-38de024d439e"
        "ipv4_cidr_block" = "192.168.16.0/20"
        "zone" = "us-south-2"
      }
    }
    "vpc_crn" = "crn:v1:bluemix:public:is:us-south:a/713c783d9a507a53135fe6793c37cc74::vpc:r006-54a0885a-e25a-435b-9eab-c294ad9b68b1"
    "zone_id" = "9369bc83-a983-4fb8-9f26-f35275f46884"
  }
}
