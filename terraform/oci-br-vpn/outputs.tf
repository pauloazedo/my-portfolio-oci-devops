output "vpn_public_ip" {
  value       = oci_core_instance.vpn.public_ip
  description = "Public IP of the VPN server"
}

output "ssh_command" {
  value       = "ssh ubuntu@${oci_core_instance.vpn.public_ip}"
  description = "SSH command to connect to the VPN server"
}
