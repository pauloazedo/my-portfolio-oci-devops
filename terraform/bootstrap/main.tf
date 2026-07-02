terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
  required_version = ">= 1.4.0"
}

provider "oci" {
  region = var.home_region
}

# Fetch tenancy namespace (needed for S3-compatible endpoint URL)
data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.tenancy_ocid
}

# Bucket lives in root compartment, home region
# Not tied to any project compartment - survives project destroys
resource "oci_objectstorage_bucket" "tfstate" {
  compartment_id = var.tenancy_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "terraform-state"
  access_type    = "NoPublicAccess"

  versioning = "Enabled"
}
