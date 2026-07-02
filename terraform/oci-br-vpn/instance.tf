# === UBUNTU 24.04 ARM IMAGE (latest) ===
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = oci_identity_compartment.vpn.id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# === VPN INSTANCE ===
resource "oci_core_instance" "vpn" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = oci_identity_compartment.vpn.id
  display_name        = "vpn-server"
  shape               = "VM.Standard.A1.Flex"

  create_vnic_details {
    subnet_id              = oci_core_subnet.vpn.id
    display_name           = "vpn-vnic"
    hostname_label         = "vpn-server"
    assign_public_ip       = true
    skip_source_dest_check = true
    nsg_ids                = [oci_core_network_security_group.nsg.id]
  }

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(<<-EOT
      #cloud-config
      package_update: true
      package_upgrade: false
      packages:
        - wireguard
        - wireguard-tools
      runcmd:
        # Enable IP forwarding for WireGuard NAT
        - echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        - sysctl -p
        # OCI Ubuntu images ship with a catch-all REJECT rule at the end of both
        # the INPUT and FORWARD chains. We insert our rules at position 1 so they
        # are evaluated before that catch-all, regardless of how many other rules
        # OCI may have added before us.
        #
        # INPUT: allow WireGuard handshake packets
        - iptables -I INPUT 1 -p udp --dport 51820 -j ACCEPT
        #
        # FORWARD: allow traffic to/from the wg0 tunnel interface.
        # WireGuard's default PostUp uses -A (append), which lands AFTER the
        # REJECT rule and never gets evaluated. We fix that by inserting at the
        # front of the chain permanently, so PostUp's duplicate -A rules are
        # harmless and PostDown's -D only removes the appended duplicates.
        - iptables -I FORWARD 1 -i wg0 -j ACCEPT
        - iptables -I FORWARD 2 -o wg0 -j ACCEPT
        #
        # Persist so rules survive reboot
        - mkdir -p /etc/iptables
        - iptables-save > /etc/iptables/rules.v4
    EOT
    )
  }

  preserve_boot_volume = false
}
