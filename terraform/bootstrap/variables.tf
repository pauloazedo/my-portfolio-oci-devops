variable "tenancy_ocid" {
  type        = string
  description = "OCI tenancy OCID"
}

variable "home_region" {
  type        = string
  description = "OCI home region"
  default     = "us-ashburn-1"
}
