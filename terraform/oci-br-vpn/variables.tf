variable "tenancy_ocid" {
  type        = string
  description = "OCI tenancy OCID"
}

variable "region" {
  type        = string
  description = "OCI region for compute resources"
  default     = "sa-saopaulo-1"
}

variable "home_region" {
  type        = string
  description = "OCI home region for IAM resources (compartments)"
  default     = "us-ashburn-1"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for instance access"
}

variable "admin_ip" {
  type        = string
  description = "Your public IP for SSH access (CIDR notation, e.g. 1.2.3.4/32)"
}
