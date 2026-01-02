# Jool NAT64 Role

This Ansible role deploys Jool NAT64 (IPv6 to IPv4 translation) with automatic Secure Boot handling.

## Features

- ✅ **Jool NAT64**: Stateful NAT64 translation (IPv6 → IPv4) using 64:ff9b::/96 prefix
- ✅ **Automatic Secure Boot Disable**: Via Proxmox SSH (no manual intervention)
- ✅ **Optional DNS64**: Unbound DNS64 server (disabled by default - RouterOS handles DNS64)

## Requirements

- Debian-based system (tested on Debian 13/Trixie)
- Kernel headers matching the running kernel
- Internet connectivity (to download Jool packages)
- Proxmox VE host with SSH access (for automatic Secure Boot disable)
- SSH key-based authentication from Ansible controller to Proxmox host

## Role Variables

### Core Configuration

```yaml
# Jool version to install
jool_version: "4.1.14"

# NAT64 prefix (must match DNS64 prefix)
jool_pool6_prefix: "64:ff9b::/96"

# System IP addresses
system_ipv4_address: "10.0.200.64"  # For NAT64 translation
system_ipv6_address: "fd00:200::64" # DNS64 listener
```

### DNS64 Configuration

```yaml
# Enable DNS64 server
dns64_enable: true

# DNS64 listen address (IPv6 only)
dns64_listen_address: "{{ system_ipv6_address }}"

# Upstream DNS servers (IPv4)
dns64_upstream_dns:
  - "1.1.1.1"
  - "1.0.0.1"

# DNS64 prefix (NAT64 well-known prefix)
dns64_prefix: "{{ jool_pool6_prefix }}"

# Domains with broken native IPv6 - force NAT64 synthesis
dns64_force_nat64_domains:
  - quay.io
  - ghcr.io
```

### Secure Boot Configuration

```yaml
# Option 1: Automatically disable Secure Boot via Proxmox (Recommended for lab)
disable_secure_boot: true
proxmox_api_host: "fd00:100::1"  # Proxmox host IPv6 address
proxmox_vm_id: "200064"  # VM ID in Proxmox

# Option 2: Enable module signing for Secure Boot (Production)
dkms_sign_modules: false  # Set to true to enable MOK signing
dkms_sign_dir: /var/lib/dkms/signing
dkms_mok_cn: "MOK for {{ inventory_hostname }}"
dkms_mok_password: "ChangeMe-Temporary-MOK-Pass"
```

**Important:**
- Set `disable_secure_boot: true` for automatic Secure Boot disable (easiest)
- OR set `dkms_sign_modules: true` for MOK signing workflow (requires manual MOK enrollment)
- Do NOT enable both options

## Usage

### 1. Create Inventory

```ini
# inventory/jool.ini
[jool]
jool ansible_host=fd00:200::64 ansible_user=root

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### 2. Create Host Variables

```yaml
# inventory/host_vars/jool.yml
system_ipv4_address: "10.0.200.64"
system_ipv6_address: "fd00:200::64"

# Add any domains with broken IPv6
dns64_force_nat64_domains:
  - quay.io
  - ghcr.io
  - registry.example.com
```

### 3. Run the Playbook

**Option A: With Automatic Secure Boot Disable (Recommended)**

```bash
# Single run - Ansible will disable Secure Boot automatically
ansible-playbook -i inventory/jool.ini playbooks/jool.yml
```

The playbook will:
1. Connect to Proxmox host via SSH
2. Stop the VM
3. Remove and recreate EFI disk without Secure Boot
4. Start the VM
5. Install and configure Jool + DNS64

**Option B: With Manual MOK Enrollment**

Set `disable_secure_boot: false` and `dkms_sign_modules: true`, then:

```bash
# First run
ansible-playbook -i inventory/jool.ini playbooks/jool.yml

# Reboot and enroll MOK at blue screen
# Then run again
ansible-playbook -i inventory/jool.ini playbooks/jool.yml
```

## Secure Boot Workflow

### Initial Run
1. Role detects Secure Boot is enabled
2. Generates MOK (Machine Owner Key) certificate
3. Configures DKMS to sign modules automatically
4. Stages MOK enrollment for next boot
5. **Triggers reboot** (via handler)

### After Reboot
1. Blue MOK Manager screen appears
2. User enrolls MOK by entering password
3. System boots with MOK enrolled

### Second Run
4. Role verifies MOK is enrolled
5. Builds and signs Jool kernel module
6. Loads signed module
7. Configures NAT64 and DNS64

## Verification

### Check Jool NAT64

```bash
# Verify module is loaded
lsmod | grep jool

# Check NAT64 instance
jool instance display

# Check NAT64 pool
jool pool6 display
```

### Check DNS64

```bash
# Test DNS64 resolution
dig @::1 AAAA github.com
# Should return 64:ff9b::... address

# Test forced NAT64 for quay.io
dig @::1 AAAA quay.io
# Should return 64:ff9b::... addresses (not 2600:1f16::...)

# Check Unbound status
systemctl status unbound
```

### Test End-to-End

```bash
# From an IPv6-only client, configure DNS to use the Jool VM
# Then test:
ping6 google.com
curl -6 https://quay.io
```

## Troubleshooting

### Secure Boot Issues

```bash
# Check Secure Boot state
mokutil --sb-state

# List enrolled MOKs
mokutil --list-enrolled

# Check if MOK enrollment is pending
mokutil --list-new
```

### Module Loading Issues

```bash
# Check if module is signed
modinfo jool | grep sig

# Try loading manually
modprobe jool

# Check dmesg for errors
dmesg | grep jool
```

### DNS64 Issues

```bash
# Check Unbound configuration
unbound-checkconf

# Test DNS64 directly
dig @::1 AAAA example.com +short

# Check Unbound logs
journalctl -u unbound -f
```

## Architecture

```
┌─────────────────────────────────────────┐
│         IPv6-Only Clients               │
│    (K8s nodes, containers, etc.)        │
│    DNS: fd00:0:0:ffff::fffe (RouterOS)       │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  RouterOS DNS (fd00:0:0:ffff::fffe)          │
│  - Authoritative for local zones        │
│  - Forwards to Jool for DNS64           │
│  - Static overrides (quay.io, etc.)     │
└──────────────┬──────────────────────────┘
               │ Forward to Jool
┌──────────────▼──────────────────────────┐
│         Jool VM (fd00:200::64)          │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │   Unbound DNS64                 │   │
│  │   - Synthesize AAAA from A      │   │
│  │   - Override broken domains     │   │
│  │   - Return 64:ff9b::/96 addrs   │   │
│  └──────────────┬──────────────────┘   │
│                 │                       │
│  ┌──────────────▼──────────────────┐   │
│  │   Jool NAT64 (kernel module)    │   │
│  │   - Translate IPv6 ↔ IPv4       │   │
│  │   - Pool: 64:ff9b::/96          │   │
│  └──────────────┬──────────────────┘   │
└─────────────────┼───────────────────────┘
                  │ 10.0.200.64
┌─────────────────▼───────────────────────┐
│         IPv4 Internet                    │
│    (quay.io, ghcr.io, etc.)             │
└──────────────────────────────────────────┘
```

### Integration Steps

**After deploying the Jool VM:**

1. **Configure RouterOS to forward to Jool DNS64:**
   ```routeros
   /ip dns set servers=fd00:200::64
   ```

2. **Remove temporary RouterOS static DNS entries:**
   ```routeros
   /ip dns static remove [find name=quay.io]
   /ip dns static remove [find name=ghcr.io]
   ```

3. **Clients continue using RouterOS DNS** - No client reconfiguration needed
   - K8s nodes: `fd00:0:0:ffff::fffe`
   - Other clients: `fd00:101::fffe`

The Jool role only manages the Jool VM itself. Network-level DNS configuration (RouterOS forwarding) is managed separately.

## Tags

- `install`: Install packages only
- `configure`: Configure services only
- `dns64`: DNS64-specific tasks

Example:
```bash
# Only install packages
ansible-playbook -i inventory/jool.ini playbooks/jool.yml --tags install

# Skip DNS64 configuration
ansible-playbook -i inventory/jool.ini playbooks/jool.yml --skip-tags dns64
```

## License

MIT

## Author

Created for IPv6-only Kubernetes deployments with NAT64/DNS64 support.
