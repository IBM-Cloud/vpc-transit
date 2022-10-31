provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = local.provider_region
}
