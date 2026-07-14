# ansible/pve

Ansible for building and maintaining the PVE/Ceph/FRR cluster (pve01-04),
replacing the old `ansible/lae.proxmox` tree
(see `ansible/_archive/lae.proxmox-legacy/README.md` for what it replaced
and why).

## Bootstrap

```
ansible-galaxy collection install -r requirements.yml
```

Collections are not vendored in git.

## Running a from-scratch cluster build

```
ansible-playbook playbooks/site.yml
```

This runs the numbered sequence in order (`00-bootstrap-repos.yml` through
`41-ceph-osd.yml`). For a day-2 change to a single stage, run that playbook
directly instead of the whole sequence, e.g.:

```
ansible-playbook playbooks/21-frr.yml
```

## Source of truth for shared values

`inventory/group_vars/all.yml` loads two generated facts files so BGP
ASN / SDN MTU-VNI-zone / node IPs / NTP can't drift from Terraform the way
they did before the 2026-07-12 FRR power-event incident
(`docs/tickets/pve-frr-power-event-20260712.md`):

- `network_facts` <- `ansible/network-facts.json`, written by the
  `terraform/infra/live/common/3-ansible-facts` terragrunt unit from
  `network-infrastructure.hcl` locals. Run `terragrunt apply` there after
  changing BGP/SDN/RouterOS values.
- `site_facts` <- `site.json`, written by `scripts/sync-site-facts.sh` from
  `site.yaml`. Run that script after changing `site.yaml`.

Edit `network-infrastructure.hcl` / `site.yaml`, not the generated files.

## Structure

- `roles/` - PVE-specific roles (FRR, interfaces, Ceph, bootstrap, etc).
- `../common/roles/` - host-generic roles (ssh, sysctl, firewall,
  node_exporter, etc.) shared with other non-PVE ansible domains, e.g.
  `../nat64/`.
- `playbooks/` - numbered build stages + `site.yml` orchestrator, plus a
  handful of standalone day-2 maintenance playbooks
  (`ceph-osd-reconcile.yml`, `configure-test-vms.yml`, etc.) that aren't
  part of the from-scratch build sequence.
- `inventory/` - `hosts.ini` (pve/cluster/ceph_* groups + the `routeros`
  edge router host), `test-vms.ini` (separate - not auto-merged, pass
  `-i inventory/test-vms.ini` explicitly for `configure-test-vms.yml`),
  `group_vars/`, `host_vars/`.

## Retired roles (see ansible/_archive/)

- `ansible/_archive/perl_plugin-retired/` (was `perl_plugin`) - patched
  Proxmox's own stock SDN BGP controller Perl files. Retired by
  preference (patched vendor files are hard to keep track of and silently
  break on upgrade), and independently verified against current stock PVE
  source to target an older pve-network internal data model - see that
  archive's README before reviving.
- `ansible/_archive/terraform-managed-redundant/` (was `proxmox_oidc`,
  `pve_accounts`, `vnet_gua`) - retired, redundant with already-live
  Terraform: PVE RBAC (`terraform/infra/live/common/proxmox-access`), the
  OIDC realm (`.../proxmox-realms`), and SDN GUA subnets
  (`.../0-sdn-setup`). See that archive's README.
