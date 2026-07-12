# Infrastructure inventory (GENERATED - do not edit)

Source: `site.yaml`. Regenerate with `scripts/sync-site-facts.sh`.
Derived values are materialized here so they stay greppable.

## Proxmox nodes

| Node | Management IP | FQDN |
|---|---|---|
| pve01 | 10.10.0.1 | pve01.sulibot.com |
| pve02 | 10.10.0.2 | pve02.sulibot.com |
| pve03 | 10.10.0.3 | pve03.sulibot.com |

API endpoint: `https://10.10.0.2:8006/api2/json`

## Network tenants

| Tenant | Purpose | Mode | Subnets | Gateways |
|---|---|---|---|---|
| 100 | core service LXCs (kanidm, pki, tailscale) | sdn | 10.100.0.0/24, fd00:100::/64 | 10.100.0.254, fd00:100::fffe |
| 101 | cluster-101 (sol) | sdn | 10.101.0.0/24, fd00:101::/64 | 10.101.0.254, fd00:101::fffe |
| 104 | cluster-104 (baremetal) | sdn | 10.104.0.0/24, fd00:104::/64 | 10.104.0.254, fd00:104::fffe |
| 200 | shared infra (minio, zot, nixos guests) | vlan | 10.200.0.0/24, fd00:200::/64 | 10.200.0.254, fd00:200::fffe |

## Service guests

| Service | Host | OS | Tenant | Node | vm_id | IPv4 | IPv6 | Size |
|---|---|---|---|---|---|---|---|---|
| kanidm | (managed in its unit) | debian | 100 | - | - | - | - | small |
| minio | minio01 | debian | 200 | pve02 | 200052 | 10.200.0.52 | fd00:200::52 | small |
| zot | zot01 | debian | 200 | pve02 | 200051 | 10.200.0.51 | fd00:200::51 | small +ov |
| pki | pki01 | debian | 100 | pve01 | 100064 | 10.100.0.64 | fd00:100::64 | small |
| tail | tail01 | debian | 100 | pve01 | 100065 | 10.100.0.65 | fd00:100::65 | micro |
| tail | tail02 | debian | 100 | pve02 | 100066 | 10.100.0.66 | fd00:100::66 | micro |
| nixtest | nixtest01 | nixos | 200 | pve02 | 200202 | 10.200.0.202 | fd00:200::202 | micro +ov |

## Sizes

| Size | CPU | Memory | Swap | Disk |
|---|---|---|---|---|
| micro | 1 | 512 MB | 256 MB | 8 GB |
| small | 2 | 2048 MB | 512 MB | 16 GB |
| build | 6 | 16384 MB | 0 MB | 100 GB |
