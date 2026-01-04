# Test VM Network Configuration Role

This Ansible role configures network settings and BGP peering for test VMs in the tenant network.

## Features

- Configures static IPv4 and IPv6 addresses via netplan
- Sets up loopback addresses for BGP router IDs
- Deploys FRR for BGP peering with Proxmox VE
- Configures BGP to peer with ULA anycast gateway (fd00:<tenant_id>::fffe)
- Advertises VM loopback addresses via BGP
- Receives default routes (IPv4 and IPv6) from Proxmox
- Blocks Router Advertisement transmission from test VMs

## Variables

### Required Host Variables

Each host must define these variables in `inventory/host_vars/<hostname>.yml`:

```yaml
vm_ipv4: "10.101.0.6"              # VM interface IPv4 address
vm_ipv6: "fd00:101::6"             # VM interface IPv6 ULA address
vm_link_local: "fe80::101:6"       # VM interface link-local address
vm_loopback_v4: "10.101.254.6"     # VM loopback IPv4 address
vm_loopback_v6: "fd00:101:fe::6"   # VM loopback IPv6 address
vm_bgp_asn: 4200101006              # Unique BGP ASN for this VM
```

### Default Variables

Defined in `defaults/main.yml`:

```yaml
tenant_id: 101                      # Tenant/cluster ID
gateway_v4: "10.101.0.254"          # IPv4 gateway
gateway_v6: "fd00:101::fffe"        # IPv6 ULA anycast gateway
dns_server_v4: "10.255.0.53"        # IPv4 DNS server
dns_server_v6: "fd00:0:0:ffff::53"  # IPv6 DNS server
interface_mtu: 1450                 # MTU for VXLAN
bgp_remote_asn: 4200001000          # Proxmox BGP ASN
bgp_advertise_loopbacks: true       # Advertise loopback addresses
frr_version: "10.2"                 # FRR version
```

## Usage

### Apply to all test VMs:

```bash
cd /Users/sulibot/repos/github/home-ops/ansible/lae.proxmox
ansible-playbook -i inventory/test-vms.ini playbooks/configure-test-vms.yml
```

### Apply to specific VM:

```bash
ansible-playbook -i inventory/test-vms.ini playbooks/configure-test-vms.yml --limit debian-test-1
```

## BGP Architecture

- **Transport**: IPv6-only BGP session
- **Capabilities**: MP-BGP with extended-nexthop (RFC 5549)
- **IPv4 routes**: Carried over IPv6 with IPv6 next-hops
- **IPv6 routes**: Native IPv6 routing
- **Peering**: VMs connect TO fd00:<tenant_id>::fffe
- **Source**: VMs peer from their interface addresses (NOT loopback)

## Files Managed

- `/etc/netplan/50-cloud-init.yaml` - Network configuration
- `/etc/frr/frr.conf` - FRR BGP configuration
- `/etc/frr/daemons` - FRR daemon enablement
- `/etc/iptables/rules.v6` - IPv6 firewall rules

## Dependencies

- Debian/Ubuntu-based OS
- Python 3
- Root or sudo access
