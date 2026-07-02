# OCI WireGuard VPN — Brazil (São Paulo)

A WireGuard VPN server running on Oracle Cloud Infrastructure (OCI) in `sa-saopaulo-1`, giving you a Brazilian IP address. Provisioned entirely with Terraform. Terraform state is stored in OCI Object Storage via OCI CLI wrapper (see [Why not S3 backend?](#why-not-s3-backend)).

---

## Architecture

```
Mac (client)
  └── WireGuard tunnel (UDP 51820, AllowedIPs 0.0.0.0/0)
        └── OCI VM — sa-saopaulo-1 — 147.15.126.88
              ├── Compartment: vpn
              ├── VCN: 10.0.0.0/16
              ├── Subnet: 10.0.1.0/24 (public)
              ├── NSG: SSH restricted to admin IP, WireGuard open
              ├── Security List: WireGuard UDP 51820 open
              └── wg0: 10.8.0.1/24, NAT via iptables MASQUERADE
```

All traffic from the Mac routes through the OCI server in Brazil. Sites see `147.15.126.88` (Oracle Cloud, São Paulo).

---

## Is this free?

Yes, fully covered by OCI Always Free tier:

| Resource | Always Free limit | What we use |
|---|---|---|
| VM.Standard.A1.Flex | 4 OCPUs / 24 GB total | 1 OCPU / 6 GB |
| Boot volume | 200 GB total block storage | 50 GB |
| Public IP | 2 reserved IPs | 1 ephemeral IP |
| Object Storage | 20 GB | ~10 KB (tfstate) |
| **Outbound bandwidth** | **10 TB/month** | Scales with your streaming |

The 10 TB/month outbound covers even heavy video streaming usage comfortably (4K streaming at ~25 Mbps for 8 hours/day would use roughly 2.5 TB/month).

---

## Prerequisites

### Tools

```bash
# Terraform via tfenv
brew install tfenv
tfenv install 1.15.7
tfenv use 1.15.7

# OCI CLI (required for state management)
brew install oci-cli
oci setup config   # follow the prompts with your tenancy OCID, user OCID, region, key

# WireGuard (Mac client)
brew install wireguard-tools
```

### OCI credentials

Make sure `~/.oci/config` is set up and `oci iam user list` works without errors.

---

## Repository structure

```
terraform/
├── bootstrap/          # Creates the tfstate Object Storage bucket (run once)
│   ├── main.tf
│   ├── outputs.tf
│   ├── variables.tf
│   └── terraform.tfvars
└── oci-br-vpn/         # VPN infrastructure
    ├── main.tf         # Compartment, VCN, subnet, NSG, security list
    ├── instance.tf     # VM, cloud-init
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars
    └── Makefile        # Wraps terraform with OCI CLI state push/pull
```

---

## Initial deployment (first time)

### 1. Bootstrap — create the tfstate bucket

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

This creates a versioned `terraform-state` bucket in OCI Object Storage. Run once ever.

### 2. Deploy the VPN infrastructure

```bash
cd terraform/oci-br-vpn
terraform init
make apply
```

`make apply` pulls state from OCI Object Storage, runs `terraform apply`, then pushes state back.

Note the outputs:

```
vpn_public_ip = "147.15.126.88"
ssh_command   = "ssh ubuntu@147.15.126.88"
```

Cloud-init takes ~2 minutes after the instance shows as `RUNNING`. WireGuard will be installed and iptables rules will be in place before you SSH in.

---

## WireGuard server setup (manual, run after each new deployment)

These steps are manual because WireGuard private keys should never be stored in Terraform state or passed through cloud-init.

### 1. SSH into the server

```bash
ssh ubuntu@147.15.126.88
```

### 2. Generate server keys

```bash
wg genkey | sudo tee /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key
sudo chmod 600 /etc/wireguard/server_private.key
```

### 3. Create `/etc/wireguard/wg0.conf`

```bash
SERVER_PRIV=$(sudo cat /etc/wireguard/server_private.key)

sudo tee /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = ${SERVER_PRIV}
PostUp = iptables -t nat -A POSTROUTING -o enp0s6 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o enp0s6 -j MASQUERADE

[Peer]
PublicKey = PASTE_MAC_CLIENT_PUBLIC_KEY_HERE
AllowedIPs = 10.8.0.2/32
EOF

sudo chmod 600 /etc/wireguard/wg0.conf
```

> Note: The FORWARD iptables rules (`-i wg0 -j ACCEPT` / `-o wg0 -j ACCEPT`) are handled permanently by cloud-init, so PostUp only needs the NAT MASQUERADE rule.

### 4. Get the server public key

```bash
sudo cat /etc/wireguard/server_public.key
```

Keep this. You'll need it for the Mac client config.

### 5. Start WireGuard

```bash
sudo systemctl enable --now wg-quick@wg0
sudo wg show
```

---

## Mac client setup (run once, or after server is recreated)

### 1. Generate Mac keys

```bash
mkdir -p ~/.wireguard
wg genkey | tee ~/.wireguard/mac_private.key | wg pubkey | tee ~/.wireguard/mac_public.key
chmod 600 ~/.wireguard/mac_private.key
```

### 2. Create `~/.wireguard/wg0.conf`

```ini
[Interface]
PrivateKey = <contents of ~/.wireguard/mac_private.key>
Address = 10.8.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = <server public key from step 4 above>
Endpoint = 147.15.126.88:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### 3. Add Mac public key to server

Back on the server, add the peer:

```bash
sudo wg set wg0 peer <mac_public_key> allowed-ips 10.8.0.2/32
```

Or add it to `/etc/wireguard/wg0.conf` as a `[Peer]` block and restart: `sudo systemctl restart wg-quick@wg0`.

---

## Day-to-day usage

### Connect

```bash
sudo wg-quick up ~/.wireguard/wg0.conf
```

### Verify you have a Brazilian IP

```bash
curl ifconfig.me     # should show 147.15.126.88
curl https://1.1.1.1/cdn-cgi/trace   # loc=BR
```

### Disconnect

```bash
sudo wg-quick down ~/.wireguard/wg0.conf
```

### Check tunnel status (server)

```bash
ssh ubuntu@147.15.126.88 sudo wg show
```

---

## Teardown and recreation

### Destroy

```bash
cd terraform/oci-br-vpn
make destroy
```

This destroys the VM, VCN, subnet, NSG, security list, and compartment. The tfstate bucket (bootstrap) is left intact.

### Recreate

```bash
make apply
```

Then redo the [WireGuard server setup](#wireguard-server-setup-manual-run-after-each-new-deployment) section. The Mac client `wg0.conf` only needs updating if the server public key or IP changes.

Note: OCI may assign a different public IP on recreation. Update `Endpoint` in `~/.wireguard/wg0.conf` if it does.

---

## Troubleshooting

### No handshake / tunnel not working

Check all three firewall layers — OCI has three independent layers that all must pass:

| Layer | Where | Check |
|---|---|---|
| NSG | OCI network | Terraform manages this |
| Security List | OCI subnet | Terraform manages this |
| iptables INPUT | OS | `sudo iptables -L INPUT -n --line-numbers` |
| iptables FORWARD | OS | `sudo iptables -L FORWARD -n --line-numbers` |

For INPUT, UDP 51820 must appear before the catch-all REJECT. For FORWARD, wg0 accept rules must appear before REJECT. Cloud-init handles both by inserting at position 1. If rules are missing:

```bash
sudo iptables -I INPUT 1 -p udp --dport 51820 -j ACCEPT
sudo iptables -I FORWARD 1 -i wg0 -j ACCEPT
sudo iptables -I FORWARD 2 -o wg0 -j ACCEPT
sudo sh -c "iptables-save > /etc/iptables/rules.v4"
```

### DNS fails with VPN up but IP-based requests work

WireGuard's PostUp sets DNS to 1.1.1.1 on all interfaces. DNS queries go through the tunnel. If the tunnel isn't forwarding traffic correctly, DNS fails. Fix the FORWARD rules above.

### SSH stops working with VPN up

It shouldn't — `wg-quick` adds a specific host route for `147.15.126.88` via your real gateway, so SSH bypasses the tunnel. If SSH fails, bring the tunnel down first: `sudo wg-quick down ~/.wireguard/wg0.conf`.

### Terraform apply fails on VCN creation (404)

IAM compartment propagation delay. The `time_sleep` resource in `main.tf` waits 60 seconds. If you see this error, just re-run `make apply`.

---

## Why not S3 backend?

OCI's S3-compatible API returns `501 Not Implemented` for `aws-chunked` transfer encoding, which is used by the Terraform Go SDK v2 S3 backend. This affects all Terraform 1.x versions and is an OCI API limitation.

Workaround: local backend + `Makefile` that uses the OCI CLI (native API) to push/pull state to/from the `terraform-state` bucket. The Makefile targets (`make apply`, `make plan`, `make destroy`) handle the state sync transparently.

---

## Key values

After `make apply`, get the server IP from Terraform outputs:

```bash
terraform output vpn_public_ip
```

Fixed values:

| Item | Value |
|---|---|
| WireGuard subnet | `10.8.0.0/24` |
| Server WireGuard address | `10.8.0.1` |
| Client WireGuard address | `10.8.0.2` |
| OCI region | `sa-saopaulo-1` |
| OCI home region | `us-ashburn-1` |
| tfstate bucket | `terraform-state` |
| tfstate key | `oci-br-vpn/terraform.tfstate` |
