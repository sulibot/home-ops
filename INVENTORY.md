# Infrastructure inventory (GENERATED - do not edit)

Source: `site.yaml`. Regenerate with `scripts/sync-site-facts.sh`.
Derived values are materialized here so they stay greppable.

## Proxmox nodes

| Node | Management IP | FQDN |
|---|---|---|
| pve01 | 10.10.0.1 | pve01.sulibot.com |
| pve02 | 10.10.0.2 | pve02.sulibot.com |
| pve03 | 10.10.0.3 | pve03.sulibot.com |

API endpoint: `https://10.10.0.1:8006/api2/json`

## Network tenants

| Tenant | Purpose | Mode | Subnets | Gateways |
|---|---|---|---|---|
| 100 | core service LXCs (kanidm, openbao, pki, tailscale) | sdn | 10.100.0.0/24, fd00:100::/64 | 10.100.0.254, fd00:100::fffe |
| 101 | cluster-101 (sol) | sdn | 10.101.0.0/24, fd00:101::/64 | 10.101.0.254, fd00:101::fffe |
| 104 | cluster-104 (baremetal) | sdn | 10.104.0.0/24, fd00:104::/64 | 10.104.0.254, fd00:104::fffe |
| 200 | shared infra (minio, zot, nixos guests) | vlan | 10.200.0.0/24, fd00:200::/64 | 10.200.0.254, fd00:200::fffe |

## Service guests

| Service | Host | OS | Tenant | Node | vm_id | IPv4 | IPv6 | Size |
|---|---|---|---|---|---|---|---|---|
| kanidm | (managed in its unit) | debian | 100 | - | - | - | - | small |
| openbao | openbao01 | debian | 100 | pve01 | 100068 | 10.100.0.68 | fd00:100::68 | micro +ov |
| openbao | openbao02 | debian | 100 | pve02 | 100069 | 10.100.0.69 | fd00:100::69 | micro +ov |
| openbao | openbao03 | debian | 100 | pve03 | 100070 | 10.100.0.70 | fd00:100::70 | micro +ov |
| minio | minio01 | debian | 200 | pve02 | 200052 | 10.200.0.52 | fd00:200::52 | small |
| zot | zot01 | debian | 200 | pve02 | 200051 | 10.200.0.51 | fd00:200::51 | small +ov |
| pki | pki01 | debian | 100 | pve01 | 100064 | 10.100.0.64 | fd00:100::64 | small |
| tail | tail01 | debian | 100 | pve01 | 100065 | 10.100.0.65 | fd00:100::65 | micro |
| tail | tail02 | debian | 100 | pve02 | 100066 | 10.100.0.66 | fd00:100::66 | micro |
| nixtest | nixtest01 | nixos | 200 | pve02 | 200202 | 10.200.0.202 | fd00:200::202 | micro +ov |
| nixfs-vm | nixfs-vm01 | nixos | 200 | pve01 | 200203 | 10.200.0.203 | fd00:200::203 | small |
| nixfs-lxc | nixfs-lxc01 | nixos | 200 | pve02 | 200204 | 10.200.0.204 | fd00:200::204 | micro +ov |
| debfs-vm | debfs-vm01 | debian | 200 | pve03 | 200205 | 10.200.0.205 | fd00:200::205 | small |
| debfs-lxc | debfs-lxc01 | debian | 200 | pve01 | 200206 | 10.200.0.206 | fd00:200::206 | micro |
| agent-devbox | agent-devbox01 | nixos | 200 | pve02 | 200210 | 10.200.0.210 | fd00:200::210 | small +ov |
| nfs-gateway | nfsgw01 | debian | 200 | pve01 | 200207 | 10.200.0.207 | fd00:200::207 | micro +ov |
| nfs-gateway | nfsgw02 | debian | 200 | pve02 | 200208 | 10.200.0.208 | fd00:200::208 | micro +ov |

## Sizes

| Size | CPU | Memory | Swap | Disk |
|---|---|---|---|---|
| micro | 1 | 512 MB | 256 MB | 8 GB |
| small | 2 | 2048 MB | 512 MB | 16 GB |
| build | 6 | 16384 MB | 0 MB | 100 GB |
