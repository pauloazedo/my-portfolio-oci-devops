output "namespace" {
  value       = data.oci_objectstorage_namespace.ns.namespace
  description = "OCI Object Storage namespace - use this in the backend endpoint URL"
}

output "backend_endpoint" {
  value       = "https://${data.oci_objectstorage_namespace.ns.namespace}.compat.objectstorage.${var.home_region}.oraclecloud.com"
  description = "S3-compatible endpoint for Terraform backend configuration"
}
