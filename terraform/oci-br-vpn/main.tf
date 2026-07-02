terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }
  required_version = ">= 1.4.0"

  # State is managed via OCI CLI (see Makefile) to avoid S3 chunked encoding
  # incompatibility between Terraform Go SDK v2 and OCI S3-compatible API.
  backend "local" {
    path = "terraform.tfstate"
  }
}

# IAM resources (compartments) must target the home region
provider "oci" {
  alias  = "home"
  region = var.home_region
}

# Compute resources target Brazil
provider "oci" {
  region = var.region
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# === COMPARTMENT ===
resource "oci_identity_compartment" "vpn" {
  provider      = oci.home
  name          = "vpn"
  description   = "WireGuard VPN server - Brazil"
  enable_delete = true
}

# IAM compartments take time to propagate across regions
resource "time_sleep" "wait_for_compartment" {
  depends_on      = [oci_identity_compartment.vpn]
  create_duration = "60s"
}

# === VCN ===
resource "oci_core_virtual_network" "vcn" {
  depends_on     = [time_sleep.wait_for_compartment]
  compartment_id = oci_identity_compartment.vpn.id
  display_name   = "vpn-vcn"
  cidr_block     = "10.0.0.0/16"
  dns_label      = "vpnvcn"
}

# === INTERNET GATEWAY ===
resource "oci_core_internet_gateway" "igw" {
  compartment_id = oci_identity_compartment.vpn.id
  display_name   = "vpn-igw"
  vcn_id         = oci_core_virtual_network.vcn.id
}

# === ROUTE TABLE ===
resource "oci_core_route_table" "rt" {
  compartment_id = oci_identity_compartment.vpn.id
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "vpn-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

# === SUBNET ===
resource "oci_core_subnet" "vpn" {
  compartment_id             = oci_identity_compartment.vpn.id
  vcn_id                     = oci_core_virtual_network.vcn.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "vpn-subnet"
  route_table_id             = oci_core_route_table.rt.id
  dns_label                  = "vpn"
  prohibit_public_ip_on_vnic = false
}

# === NETWORK SECURITY GROUP ===
resource "oci_core_network_security_group" "nsg" {
  compartment_id = oci_identity_compartment.vpn.id
  vcn_id         = oci_core_virtual_network.vcn.id
  display_name   = "vpn-nsg"
}

resource "oci_core_network_security_group_security_rule" "allow_ssh" {
  network_security_group_id = oci_core_network_security_group.nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source_type               = "CIDR_BLOCK"
  source                    = var.admin_ip
  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
  description = "Allow SSH from admin IP"
}

resource "oci_core_network_security_group_security_rule" "allow_wireguard" {
  network_security_group_id = oci_core_network_security_group.nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source_type               = "CIDR_BLOCK"
  source                    = "0.0.0.0/0"
  udp_options {
    destination_port_range {
      min = 51820
      max = 51820
    }
  }
  description = "Allow WireGuard UDP"
}

# Allow WireGuard on the default security list (NSG alone is not enough in OCI)
resource "oci_core_default_security_list" "default" {
  manage_default_resource_id = oci_core_virtual_network.vcn.default_security_list_id

  ingress_security_rules {
    protocol = "17"
    source   = "0.0.0.0/0"
    udp_options {
      min = 51820
      max = 51820
    }
    description = "Allow WireGuard UDP"
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    description = "Allow all egress"
  }
}

resource "oci_core_network_security_group_security_rule" "allow_egress" {
  network_security_group_id = oci_core_network_security_group.nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination_type          = "CIDR_BLOCK"
  destination               = "0.0.0.0/0"
  description               = "Allow all egress"
}
