#!/usr/bin/env bash
# Regenerate the derived views of site.yaml:
#   site.json     - consumed by Terragrunt (jsondecode) and Nix (fromJSON)
#   INVENTORY.md  - every derived value materialized, human-readable + greppable
# Run after any edit to site.yaml. CI fails if these are stale.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# kislyuk/yq emits JSON by default
yq --indent 2 '.' site.yaml > site.json
# The nix/ flake cannot read outside its own root in pure eval mode
cp site.json nix/site.json

python3 - <<'PYEOF'
import json

site = json.load(open('site.json'))
tenants = {int(k): v for k, v in site['tenants'].items()}
sizes = site['sizes']

def derive(tenant, suffix):
    return {
        'ipv4': f"10.{tenant}.0.{suffix}",
        'ipv6': f"fd00:{tenant}::{suffix}",
        'vm_id': tenant * 1000 + suffix,
        'gw4': f"10.{tenant}.0.254",
        'gw6': f"fd00:{tenant}::fffe",
        'bridge': f"vnet{tenant}" if tenants[tenant]['mode'] == 'sdn' else f"vmbr0 (vlan {tenant})",
    }

lines = [
    "# Infrastructure inventory (GENERATED - do not edit)",
    "",
    "Source: `site.yaml`. Regenerate with `scripts/sync-site-facts.sh`.",
    "Derived values are materialized here so they stay greppable.",
    "",
    "## Proxmox nodes",
    "",
    "| Node | Management IP | FQDN |",
    "|---|---|---|",
]
domain = site['domain']
for name, node in site['proxmox']['nodes'].items():
    lines.append(f"| {name} | {node['mgmt_ip']} | {name}.{domain} |")
lines += [
    "",
    f"API endpoint: `{site['proxmox']['api_endpoint']}`",
    "",
    "## Network tenants",
    "",
    "| Tenant | Purpose | Mode | Subnets | Gateways |",
    "|---|---|---|---|---|",
]
for tid, t in sorted(tenants.items()):
    lines.append(
        f"| {tid} | {t['purpose']} | {t['mode']} | 10.{tid}.0.0/24, fd00:{tid}::/64 "
        f"| 10.{tid}.0.254, fd00:{tid}::fffe |")
lines += [
    "",
    "## Service guests",
    "",
    "| Service | Host | OS | Tenant | Node | vm_id | IPv4 | IPv6 | Size |",
    "|---|---|---|---|---|---|---|---|---|",
]
for sname, svc in site['services'].items():
    os_ = svc.get('os', 'debian')
    size = svc.get('size', '-')
    ov = svc.get('override', {})
    size_note = size + (' +ov' if any(k in ov for k in ('cpu_cores','memory_mb','swap_mb','disk_gb')) else '')
    if svc.get('multi_instance'):
        lines.append(f"| {sname} | (managed in its unit) | {os_} | {svc['tenant']} | - | - | - | - | {size_note} |")
        continue
    insts = svc.get('instances') or {sname: {'suffix': svc['suffix'], 'node': svc['node'],
                                             'hostname': svc.get('hostname', sname)}}
    for iname, inst in insts.items():
        d = derive(svc['tenant'], inst['suffix'])
        host = inst.get('hostname', iname)
        lines.append(
            f"| {sname} | {host} | {os_} | {svc['tenant']} | {inst['node']} "
            f"| {d['vm_id']} | {d['ipv4']} | {d['ipv6']} | {size_note} |")
lines += [
    "",
    "## Sizes",
    "",
    "| Size | CPU | Memory | Swap | Disk |",
    "|---|---|---|---|---|",
]
for sname, s in sizes.items():
    lines.append(f"| {sname} | {s['cpu_cores']} | {s['memory_mb']} MB | {s['swap_mb']} MB | {s['disk_gb']} GB |")
lines.append("")

open('INVENTORY.md', 'w').write('\n'.join(lines))
print("wrote site.json + INVENTORY.md")
PYEOF
