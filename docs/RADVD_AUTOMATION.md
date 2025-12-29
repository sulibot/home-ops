# radvd and IPv6 GUA Automation for Tenant VNets

## Overview

This document describes the Ansible automation implemented to configure IPv6 Router Advertisements (radvd) and Global Unicast Addresses (GUA) on Proxmox SDN tenant VNets, enabling VMs to obtain both ULA and GUA IPv6 addresses via SLAAC for internet connectivity.

## Problem Statement

VMs in the EVPN tenant network (vrf_evpnz1) were only receiving ULA IPv6 addresses (fd00::/8) via SLAAC, preventing them from reaching the IPv6 internet. The anycast gateway on PVE hosts was not advertising Router Advertisements with GUA prefixes from AT&T's DHCPv6 Prefix Delegation.

## Solution Components

### 1. Router Advertisement Daemon (radvd)

**Package**: `radvd`
**Purpose**: Advertises IPv6 prefixes to VMs for SLAAC address assignment
**Configuration**: `/etc/radvd.conf`

The radvd daemon runs on all PVE nodes (pve01, pve02, pve03) and advertises both ULA and GUA prefixes on each tenant vnet interface.

### 2. IPv6 GUA Address Configuration

**Purpose**: Configures GUA addresses on tenant vnet interfaces
**Configuration**: `/etc/network/interfaces.d/91-tenant-vnet-gua`

Each vnet receives a GUA address from the AT&T delegated prefix with the host portion `::ffff/64` to serve as the anycast gateway.

### 3. FRR Static Routes

**Purpose**: Routes return traffic from default VRF into vrf_evpnz1
**Configuration**: FRR configuration via `/etc/frr/frr.conf`

Static routes in the default VRF direct GUA prefix traffic into the tenant VRF (vrf_evpnz1) so that return packets from the internet can reach VMs.

## AT&T Prefix Delegation Mapping

AT&T delegates 3 IPv6 /64 prefixes via DHCPv6 PD to RouterOS:

| Prefix | Original Use (RouterOS) | New Use (Tenant VNet) |
|--------|-------------------------|----------------------|
| `2600:1700:ab1a:500c::/64` | vlan10 clients | vnet100 |
| `2600:1700:ab1a:500d::/64` | vlan30 clients | vnet101 |
| `2600:1700:ab1a:500f::/64` | vlan200 clients | vnet102 |

**Note**: vnet103 only uses ULA prefix as AT&T only delegates 3 prefixes.

## Ansible Automation

### Files Created/Modified

#### 1. `ansible/lae.proxmox/playbooks/group_vars/pve.yml`

Updated the `tenant_vnets` variable from a simple list to a structured list of dictionaries:

```yaml
tenant_vnets:
  - name: vnet100
    id: 100
    ipv4_subnet: "10.100.0.0/24"
    ula_prefix: "fd00:100::/64"
    gua_prefix: "2600:1700:ab1a:500c::/64"
  - name: vnet101
    id: 101
    ipv4_subnet: "10.101.0.0/24"
    ula_prefix: "fd00:101::/64"
    gua_prefix: "2600:1700:ab1a:500d::/64"
  - name: vnet102
    id: 102
    ipv4_subnet: "10.102.0.0/24"
    ula_prefix: "fd00:102::/64"
    gua_prefix: "2600:1700:ab1a:500f::/64"
  - name: vnet103
    id: 103
    ipv4_subnet: "10.103.0.0/24"
    ula_prefix: "fd00:103::/64"
    # No GUA prefix - only 3 PD delegations available
```

Legacy compatibility variables (`VNET_IDS`, `VNET_V4_SUBNETS`, `VNET_ULA_SUBNETS`, `VNET_GUA_PREFIXES`) are automatically generated from this structure.

#### 2. `ansible/lae.proxmox/roles/interfaces/templates/radvd.conf.j2`

Jinja2 template for radvd configuration:

```jinja2
{% for vnet in tenant_vnets %}
interface {{ vnet.name }} {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    AdvManagedFlag off;
    AdvOtherConfigFlag off;

    # ULA prefix
    prefix {{ vnet.ula_prefix }} {
        AdvOnLink on;
        AdvAutonomous on;
        AdvRouterAddr on;
    };

{% if vnet.gua_prefix is defined %}
    # GUA prefix from AT&T PD
    prefix {{ vnet.gua_prefix }} {
        AdvOnLink on;
        AdvAutonomous on;
        AdvRouterAddr on;
    };
{% endif %}
};
{% endfor %}
```

#### 3. `ansible/lae.proxmox/roles/interfaces/templates/tenant_vnet_ipv6_gua.j2`

Template for configuring GUA addresses on vnet interfaces:

```jinja2
{% for vnet in tenant_vnets %}
{% if vnet.gua_prefix is defined %}
# {{ vnet.name }} - GUA from AT&T PD
auto {{ vnet.name }}
iface {{ vnet.name }} inet6 static
    address {{ vnet.gua_prefix | regex_replace('::/64$', '::ffff/64') }}

{% endif %}
{% endfor %}
```

This creates stanzas in `/etc/network/interfaces.d/91-tenant-vnet-gua` like:

```
auto vnet100
iface vnet100 inet6 static
    address 2600:1700:ab1a:500c::ffff/64
```

#### 4. `ansible/lae.proxmox/roles/interfaces/tasks/main.yaml`

Added tasks to:
- Install radvd package
- Deploy radvd configuration from template
- Enable and start radvd service
- Deploy tenant VNet GUA address configuration
- Reload network interfaces

```yaml
- name: Install radvd package
  ansible.builtin.apt:
    name: radvd
    state: present
    update_cache: yes
  when:
    - inventory_hostname in ['pve01','pve02','pve03']

- name: Deploy radvd configuration
  ansible.builtin.template:
    src: radvd.conf.j2
    dest: /etc/radvd.conf
    mode: '0644'
    owner: root
    group: root
  notify: Restart radvd
  when:
    - inventory_hostname in ['pve01','pve02','pve03']

- name: Enable and start radvd service
  ansible.builtin.systemd:
    name: radvd
    enabled: yes
    state: started
  when:
    - inventory_hostname in ['pve01','pve02','pve03']

- name: Deploy tenant VNet GUA address configuration
  ansible.builtin.template:
    src: tenant_vnet_ipv6_gua.j2
    dest: /etc/network/interfaces.d/91-tenant-vnet-gua
    mode: '0644'
  when:
    - inventory_hostname in ['pve01','pve02','pve03']

- name: Apply network reload after tenant VNet GUA configuration
  ansible.builtin.command: /usr/sbin/ifreload -a
  when:
    - inventory_hostname in ['pve01','pve02','pve03']
  changed_when: false
```

#### 5. `ansible/lae.proxmox/roles/interfaces/handlers/main.yml`

Created handlers file with:

```yaml
- name: Reload network
  ansible.builtin.command: /usr/sbin/ifreload -a
  changed_when: false

- name: Restart radvd
  ansible.builtin.systemd:
    name: radvd
    state: restarted
```

#### 6. `ansible/lae.proxmox/roles/frr/templates/frr-pve.conf.j2`

Updated to use variable-driven GUA static routes:

```jinja2
!
! GUA routes from AT&T PD for tenant networks
{% for vnet in tenant_vnets %}
{% if vnet.gua_prefix is defined %}
ipv6 route {{ vnet.gua_prefix }} {{ TENANT_VRF }}
{% endif %}
{% endfor %}
!
```

This generates routes like:

```
ipv6 route 2600:1700:ab1a:500c::/64 vrf_evpnz1
ipv6 route 2600:1700:ab1a:500d::/64 vrf_evpnz1
ipv6 route 2600:1700:ab1a:500f::/64 vrf_evpnz1
```

#### 7. `ansible/lae.proxmox/roles/interfaces/defaults/main.yml`

Removed duplicate `tenant_vnets` variable definition since it's now in group_vars/pve.yml.

## How It Works

### Packet Flow: VM to Internet

1. **VM generates traffic** to IPv6 internet (e.g., 2001:4860:4860::8888)
2. **Source address selection**: VM uses GUA address obtained via SLAAC (e.g., 2600:1700:ab1a:500d::beef)
3. **Default route**: Packet forwarded to anycast gateway (fe80::be24:11ff:fe28:2725 on vnet101)
4. **EVPN Type-2 route**: PVE host looks up destination in vrf_evpnz1 routing table
5. **Default route in tenant VRF**: `::/0 via fe80::ff:fe00:1 dev vmbr0.10 nexthop-vrf default`
6. **VRF route leak**: Packet exits vrf_evpnz1 into default VRF via vmbr0.10
7. **Default VRF routing**: Packet routed to RouterOS (fe80::aab8:e0ff:fe04:4aec%vmbr0.10)
8. **RouterOS NAT/routing**: Packet forwarded to internet via ether-wan

### Packet Flow: Internet to VM (Return Traffic)

1. **Return packet arrives** at RouterOS from internet with destination 2600:1700:ab1a:500d::beef
2. **RouterOS static route**: `2600:1700:ab1a:500d::/64 via fe80::aab8:e0ff:fe04:4aec%vlan10`
3. **Packet forwarded to PVE cluster** via vlan10 (vmbr0.10 on PVE hosts)
4. **Default VRF receives packet** on vmbr0.10
5. **Static route in default VRF**: `2600:1700:ab1a:500d::/64 dev vrf_evpnz1` (configured by FRR)
6. **VRF route leak**: Packet enters vrf_evpnz1
7. **EVPN lookup**: FRR looks up MAC/IP in EVPN Type-2 routes
8. **VXLAN encapsulation**: Packet encapsulated and forwarded to correct VTEP (PVE host where VM resides)
9. **VXLAN decapsulation**: Destination PVE host decapsulates packet
10. **VM receives packet**: Packet delivered to VM via vnet101 bridge

## Configuration Variables

### Primary Variable: `tenant_vnets`

Defined in `group_vars/pve.yml`, this structured variable drives all templates:

```yaml
tenant_vnets:
  - name: vnet100              # Interface name
    id: 100                    # VNet ID (for compatibility)
    ipv4_subnet: "10.100.0.0/24"
    ula_prefix: "fd00:100::/64"
    gua_prefix: "2600:1700:ab1a:500c::/64"  # Optional - from AT&T PD
```

### Derived Variables (Legacy Compatibility)

For templates still using the old format:

- `VNET_IDS`: List of vnet IDs `[100, 101, 102, 103]`
- `VNET_V4_SUBNETS`: Dictionary mapping IDs to IPv4 subnets
- `VNET_ULA_SUBNETS`: Dictionary mapping IDs to ULA prefixes
- `VNET_GUA_PREFIXES`: Dictionary mapping IDs to GUA prefixes (only vnets with GUA)

## Running the Automation

To deploy the configuration:

```bash
cd ansible/lae.proxmox/playbooks
ansible-playbook -i inventory site.yml --tags interfaces,frr
```

Or to run specific roles:

```bash
# Just interfaces role (includes radvd)
ansible-playbook -i inventory site.yml --tags interfaces

# Just FRR role (includes static routes)
ansible-playbook -i inventory site.yml --tags frr
```

## Verification

### Check radvd is running

```bash
ssh pve01 "systemctl status radvd"
```

### Verify Router Advertisements

On a VM:

```bash
# Show IPv6 addresses - should see both ULA and GUA
ip -6 addr show dev eth0

# Capture RAs (run for 10+ seconds to see advertisements)
radvdump
```

Expected output:

```
Router advertisement from fe80::be24:11ff:fe28:2725
  Prefix fd00:101::/64
  Prefix 2600:1700:ab1a:500d::/64
```

### Test IPv6 Internet Connectivity

From a VM:

```bash
# Should work with 0% packet loss
ping -6 -c 5 2001:4860:4860::8888
```

### Verify FRR Routes

On a PVE host:

```bash
# Check default VRF has GUA routes to tenant VRF
sudo vtysh -c "show ipv6 route" | grep 2600:1700:ab1a

# Should show routes like:
# S   2600:1700:ab1a:500c::/64 [1/0] is directly connected, vrf_evpnz1, weight 1, 00:10:23
# S   2600:1700:ab1a:500d::/64 [1/0] is directly connected, vrf_evpnz1, weight 1, 00:10:23
# S   2600:1700:ab1a:500f::/64 [1/0] is directly connected, vrf_evpnz1, weight 1, 00:10:23
```

### Verify vnet GUA addresses

On a PVE host:

```bash
# Check vnet100 has GUA address
ip -6 addr show dev vnet100 | grep 2600:1700:ab1a:500c
```

Expected:

```
inet6 2600:1700:ab1a:500c::ffff/64 scope global
```

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                        Internet (AT&T)                           │
│                 DHCPv6 PD delegations:                           │
│         500c, 500d, 500f → RouterOS (10.0.30.254)               │
└────────────────────────────┬─────────────────────────────────────┘
                             │
                             │ Static routes to PVE cluster
                             ▼
                   ┌─────────────────────┐
                   │  PVE Default VRF    │
                   │   (vmbr0.10)        │
                   │                     │
                   │  Static Routes:     │
                   │  500c → vrf_evpnz1  │
                   │  500d → vrf_evpnz1  │
                   │  500f → vrf_evpnz1  │
                   └──────────┬──────────┘
                              │
                              │ VRF route leak
                              ▼
                   ┌─────────────────────┐
                   │  vrf_evpnz1         │
                   │  (Tenant VRF)       │
                   │                     │
                   │  Default route:     │
                   │  ::/0 → default VRF │
                   └──────────┬──────────┘
                              │
                              │ EVPN Type-2 routes
                              ▼
         ┌────────────────────────────────────────────┐
         │         Tenant VNets (Anycast GW)          │
         ├────────────┬────────────┬────────────┬─────┤
         │  vnet100   │  vnet101   │  vnet102   │v103 │
         │  ::ffff    │  ::ffff    │  ::ffff    │::ffff│
         │            │            │            │     │
         │  radvd     │  radvd     │  radvd     │radvd│
         │  advertises│  advertises│  advertises│ ULA │
         │  ULA + GUA │  ULA + GUA │  ULA + GUA │only │
         └────────────┴────────────┴────────────┴─────┘
                │            │            │         │
                ▼            ▼            ▼         ▼
              VMs get     VMs get     VMs get    VMs get
           ULA + 500c   ULA + 500d  ULA + 500f  ULA only
             via SLAAC   via SLAAC   via SLAAC  via SLAAC
```

## Troubleshooting

### VMs not getting GUA addresses

1. Check radvd is running on all PVE nodes:
   ```bash
   ansible pve -i inventory -m shell -a "systemctl status radvd"
   ```

2. Check radvd configuration is deployed:
   ```bash
   ansible pve -i inventory -m shell -a "cat /etc/radvd.conf"
   ```

3. Capture RAs on a VM:
   ```bash
   ssh <vm> "timeout 15 radvdump"
   ```

### VMs have GUA but can't reach internet

1. Verify vnet interfaces have GUA addresses:
   ```bash
   ansible pve -i inventory -m shell -a "ip -6 addr show dev vnet101 | grep 2600"
   ```

2. Check FRR static routes in default VRF:
   ```bash
   ansible pve -i inventory -m shell -a "vtysh -c 'show ipv6 route' | grep 2600"
   ```

3. Verify RouterOS has static routes to PVE cluster:
   ```bash
   ssh admin@10.0.30.254 "/ipv6 route print where comment~tenant"
   ```

### Return traffic not reaching VMs

1. Check tcpdump on vmbr0.10 to see if packets are arriving:
   ```bash
   ssh pve01 "timeout 5 tcpdump -i vmbr0.10 -n 'icmp6 and src 2001:4860:4860::8888'"
   ```

2. Check if packets enter vrf_evpnz1:
   ```bash
   ssh pve01 "timeout 5 tcpdump -i vnet101 -n 'icmp6 and src 2001:4860:4860::8888'"
   ```

3. Verify EVPN Type-2 routes for VM MAC/IP:
   ```bash
   ssh pve01 "vtysh -c 'show evpn mac vni all' | grep -A 5 <vm-mac>"
   ```

## Future Enhancements

1. **Dynamic PD Updates**: Automate RouterOS configuration changes when AT&T PD changes
2. **Additional PD Prefixes**: Request 4th prefix from AT&T for vnet103
3. **Monitoring**: Add Prometheus metrics for RA advertisements and SLAAC address assignment
4. **IPv6 Firewall**: Implement stateful IPv6 firewall rules in FRR or nftables
5. **DHCPv6 Stateful**: Consider DHCPv6 server for additional configuration (DNS, NTP)

## Related Documentation

- [EVPN_Deployment.md](EVPN_Deployment.md) - EVPN architecture and configuration
- [ip-addressing-layout-2.md](ip-addressing-layout-2.md) - IPv6 addressing scheme
- [IPV6_INTERNET_CONNECTIVITY_PLAN.md](IPV6_INTERNET_CONNECTIVITY_PLAN.md) - Original IPv6 connectivity planning

## References

- [radvd Documentation](https://radvd.litech.org/)
- [RFC 4861 - Neighbor Discovery for IPv6](https://tools.ietf.org/html/rfc4861)
- [RFC 4862 - IPv6 Stateless Address Autoconfiguration](https://tools.ietf.org/html/rfc4862)
- [FRR Documentation - VRF Route Leaking](http://docs.frrouting.org/en/latest/vrf.html)
