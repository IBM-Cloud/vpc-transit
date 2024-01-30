# vpe resources are made in transit and spokes via this module
variable "make_redis" {}
variable "make_postgresql" {}
variable "make_cos" {}
variable "basename" {}
variable "tags" {}
variable "resource_group_id" {}
variable "region" {}
variable "vpc" {}
variable "subnets" {}

locals {
  tags = concat(var.tags, ["module: vpe_resources"])
}

module "redis" {
  count             = var.make_redis ? 1 : 0
  source            = "../ibm_database"
  name              = "${var.basename}-redis"
  tags              = local.tags
  resource_group_id = var.resource_group_id
  plan              = "standard"
  service           = "databases-for-redis"
  region            = var.region
  vpc               = var.vpc
  subnets           = var.subnets
}

module "postgresql" {
  count             = var.make_postgresql ? 1 : 0
  source            = "../ibm_database"
  name              = "${var.basename}-postgresql"
  tags              = local.tags
  resource_group_id = var.resource_group_id
  plan              = "standard"
  service           = "databases-for-postgresql"
  region            = var.region
  vpc               = var.vpc
  subnets           = var.subnets
}

# cos 
locals {
  # reverse engineer this by creating one by hand:
  cos_endpoint = "s3.direct.${var.region}.cloud-object-storage.appdomain.cloud"
}
resource "ibm_resource_instance" "cos" {
  count             = var.make_cos ? 1 : 0
  name              = "${var.basename}-cos"
  resource_group_id = var.resource_group_id
  service           = "cloud-object-storage"
  plan              = "standard"
  location          = "global"
  tags              = local.tags
}

resource "ibm_resource_key" "cos_key" {
  count                = var.make_cos ? 1 : 0
  name                 = "${var.basename}-cos-key"
  resource_instance_id = ibm_resource_instance.cos[0].id
  role                 = "Writer"

  parameters = {
    service-endpoints = "private"
  }
  tags = local.tags
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

resource "ibm_cos_bucket" "test" {
  count                = var.make_cos ? 1 : 0
  bucket_name          = "${var.basename}-test-${random_id.bucket_suffix.hex}"
  resource_instance_id = ibm_resource_instance.cos[0].id
  region_location      = var.region
  storage_class        = "standard"
}

resource "ibm_cos_bucket_object" "hello" {
  count           = var.make_cos ? 1 : 0
  bucket_crn      = ibm_cos_bucket.test[0].crn
  bucket_location = ibm_cos_bucket.test[0].region_location
  content         = "Hello World"
  key             = "hello"
}


resource "ibm_is_virtual_endpoint_gateway" "cos" {
  count          = var.make_cos ? 1 : 0
  vpc            = var.vpc.id
  name           = "${var.basename}-cos"
  resource_group = var.resource_group_id
  target {
    crn           = "crn:v1:bluemix:public:cloud-object-storage:global:::endpoint:${local.cos_endpoint}"
    resource_type = "provider_cloud_service"
  }

  # one Reserved IP for per zone in the VPC
  dynamic "ips" {
    for_each = { for subnet in var.subnets : subnet.id => subnet }
    content {
      subnet = ips.key
      name   = "${ips.value.name}-cos"
    }
  }
  tags = local.tags
}

locals {
  resources = flatten(concat(
    [for key, value in ibm_resource_instance.cos : {
      type         = "cos"
      key          = ibm_resource_key.cos_key[key]
      cos_endpoint = local.cos_endpoint
      bucket_name  = ibm_cos_bucket.test[key].bucket_name
      object_key   = ibm_cos_bucket_object.hello[key].key
      // hostname could be added
      virtual_endpoint_gateway = ibm_is_virtual_endpoint_gateway.cos
    }],
    [for redis in module.redis : {
      type                     = "redis"
      id                       = redis.database.id
      key                      = redis.database_key
      hostname                 = redis.database_key.credentials["connection.rediss.hosts.0.hostname"]
      virtual_endpoint_gateway = redis.virtual_endpoint_gateway
    }],
    [for postgresql in module.postgresql : {
      type     = "postgresql"
      id       = postgresql.database.id
      key      = postgresql.database_key
      hostname = postgresql.database_key.credentials["connection.postgres.hosts.0.hostname"]
    }],
  ))
  # todo
  # sensitive = true
}

output "resources" {
  value = local.resources
}
