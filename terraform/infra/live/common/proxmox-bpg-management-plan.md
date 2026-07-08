# Proxmox BPG Management Plan

This document maps Proxmox features supported by `bpg/proxmox` to the current
repo and defines the desired Terraform/Ansible ownership boundary.

## Ownership Rule

Use Terraform/BPG for Proxmox API objects that are declarative, cluster-scoped,
and safe to import/plan before apply.

Keep Ansible for host-local OS configuration, node bootstrapping, FRR/network
files, Ceph OSD lifecycle, BlueStore DB/WAL migration, CRUSH topology changes,
and anything that needs one-node-at-a-time health gates.

## 1. Access, Users, Roles, ACLs, Tokens

Status: adopted with BPG.

Current coverage:

- `terraform/infra/live/common/proxmox-access`
- `terraform/infra/modules/proxmox_access`
- imported objects: `terraform@pve`, `Terraform`, `/?terraform@pve?Terraform`,
  `terraform@pve!provider`

Older/overlapping config:

- `ansible/lae.proxmox/pve-accounts.yml`
- `ansible/lae.proxmox/roles/lae.proxmox/tasks/accounts.yml`

Recommendation:

- Keep Terraform as the owner for the Terraform service identity.
- Do not recreate API token values in Terraform unless deliberately rotating the
  token; Proxmox cannot reveal an existing token secret after creation.
- If more users, groups, roles, or ACLs are needed, add them to this Terraform
  boundary and import before apply.
- Retire or narrowly scope the Ansible account path once all intended accounts
  are represented in Terraform.

## 2. ACME and Proxmox TLS Certificates

Status: ACME account and DNS plugin adopted with BPG; certificate issuance is
deferred to a one-node maintenance test.

Current coverage:

- Legacy/manual certificate support exists in
  `ansible/lae.proxmox/roles/lae.proxmox/tasks/ssl_config.yml`.
- Kubernetes certificate management exists under GitOps, but that is separate
  from Proxmox node/UI certificates.
- Live Proxmox has an ACME account named `default` and a DNS plugin named
  `cloudflare`.
- Current BPG coverage:
  - `terraform/infra/live/common/proxmox-acme`
  - imports `default` and `cloudflare`
- `pve03` certificate reissue was tested successfully on July 7, 2026 with a
  forced one-node ACME order. See `proxmox-acme/README.md`.

Recommendation:

- Manage Proxmox ACME account, DNS plugin, and certificates with BPG if the
  Proxmox UI/API certs should be issued by Proxmox itself.
- Keep Kubernetes ingress/cert-manager certificates in Kubernetes GitOps.
- Prefer a new `terraform/infra/live/common/proxmox-acme` stack.
- Import/adopt any existing Proxmox ACME account/plugin first.
- Store DNS provider credentials in SOPS; do not put ACME plugin secrets in
  plain HCL.
- Before importing the DNS plugin, move the live plugin credential values into
  SOPS and make sure plan output does not expose them.

When not to move:

- If Proxmox certs are pushed from an external CA workflow, keep the external
  workflow as owner and document it instead of adding BPG ACME.

## 3. Backup Jobs

Status: implemented with BPG.

Current coverage:

- Kubernetes workload backup/restore is documented in `docs/backup-system.md`,
  `docs/VOLSYNC_*`, and `VOLSYNC-MIGRATION-PLAN.md`.
- Proxmox-level backup jobs were not found as Terraform-owned common stacks.
- PBS/storage terms appear in docs and Kubernetes backup planning, but no BPG
  Proxmox backup-job stack exists.
- Live Proxmox currently reports no cluster backup jobs.
- Current BPG coverage:
  - `terraform/infra/live/common/proxmox-backup-jobs`
  - creates `daily-all-guests`
- Restore-path testing succeeded with VM `200252` on July 7, 2026. Several
  stale guests were excluded from the scheduled job after backup preflight
  failures; see `proxmox-backup-jobs/README.md`.

Recommendation:

- Manage Proxmox backup jobs with BPG only for VM/LXC backups handled by
  Proxmox/PBS.
- Keep application/PVC backup policy in Kubernetes/GitOps.
- Create a `terraform/infra/live/common/proxmox-backup-jobs` stack after
  inventorying live jobs from `pvesh get /cluster/backup`.
- Import existing jobs before apply.

When not to move:

- Do not model Ceph recovery/replication or VolSync/Kopia policy as Proxmox
  backup jobs; those live in Ceph/Kubernetes layers.

## 4. HA Groups, HA Resources, HA Rules

Status: live PVE 9 HA resources/rule adopted with BPG.

Current coverage:

- Terraform has HA inputs in `terraform/infra/modules/cluster_core/main.tf`.
- `cluster_core` still has compatibility `null_resource` shims, but their
  provisioners are no-ops so future compute applies do not write HA through
  `ha-manager`.
- Cluster-level configs set HA in:
  - `terraform/infra/live/clusters/cluster-101/cluster.hcl`
  - `terraform/infra/live/clusters/cluster-102/cluster.hcl`
- Legacy Ansible HA handling also exists in
  `ansible/lae.proxmox/roles/lae.proxmox/tasks/pve_cluster_config.yml`.
- Live Proxmox reports that HA groups have been migrated to rules. Current live
  HA is one `node-affinity` rule named `sol-k8s-nodes` and six HA VM resources
  for cluster 101.
- Current BPG coverage:
  - `terraform/infra/live/common/proxmox-ha`
  - imports all six HA VM resources and the `sol-k8s-nodes` rule

Recommendation:

- Replace HA `null_resource` usage with BPG resources, favoring the current
  rule model:
  - `proxmox_harule` for node affinity
  - `proxmox_haresource` for VM membership
  - `proxmox_hagroup` only if a future cluster still needs old-style groups
- Keep the existing `proxmox_ha` input shape for compatibility, but keep the
  implementation in `terraform/infra/live/common/proxmox-ha`.
- Import existing HA groups/resources/rules before apply.
- Decide per workload whether placement is Terraform-directed or HA-directed:
  Terraform-directed placement uses `migrate = true`; HA-directed placement
  should ignore `node_name` drift for VM resources.

When not to move:

- Do not let both Ansible and Terraform manage the same HA group or resource.
  Once BPG owns HA, disable the overlapping Ansible path.

## 5. Metrics and Observability Integration

Status: empty BPG stack implemented; live Proxmox has no metrics server.

Current coverage:

- Host metrics are installed by Ansible:
  - `ansible/lae.proxmox/playbooks/stage2-host-configuration.yml`
  - `ansible/lae.proxmox/roles/node_exporter/tasks/main.yaml`
  - `ansible/lae.proxmox/roles/snmpd/tasks/main.yaml`
  - optional `ansible/lae.proxmox/roles/log_forwarding/tasks/main.yaml`
- Kubernetes observability lives under
  `kubernetes/apps/tier-1-infrastructure`.
- Live Proxmox currently reports no configured cluster metrics servers.
- Current BPG coverage:
  - `terraform/infra/live/common/proxmox-metrics`
  - intentionally manages an empty `metrics_servers` map

Recommendation:

- Use BPG `proxmox_metrics_server` only if Proxmox should push metrics to an
  external metrics backend such as InfluxDB/Graphite.
- Keep node_exporter, SNMP, and custom textfile collectors in Ansible because
  they are host packages and systemd services.
- Add BPG coverage only after deciding the destination backend and retention
  model.

When not to move:

- Do not replace node_exporter with Proxmox metrics server; they expose
  different signals and are complementary.

## 6. Storage Definitions

Status: importable local storage definitions adopted with BPG.

Current coverage:

- Central storage naming is in
  `terraform/infra/live/common/proxmox-infrastructure.hcl`.
- Ceph pools are cataloged/partially managed in
  `terraform/infra/live/common/proxmox-ceph-pools.hcl`.
- Physical OSD, CRUSH, DB/WAL, and Optane workflows stay in
  `ansible/lae.proxmox`:
  - `ansible/lae.proxmox/files/ceph-layout.md`
  - `ansible/lae.proxmox/playbooks/ceph-osd-reconcile.yml`
  - `ansible/lae.proxmox/playbooks/ceph-optane-db-migrate.yml`
- Live Proxmox storage definitions currently include `resources`, `content`,
  `config`, `local`, `rbd-vm`, and `local-zfs`.
- Current BPG coverage:
  - `terraform/infra/live/common/proxmox-storage`
  - imports `local` and `local-zfs`
  - documents that current BPG resources do not cover live CephFS/RBD storage
    definitions directly

Recommendation:

- BPG can manage stable Proxmox storage definitions such as directory, NFS, CIFS,
  PBS, LVM, LVM-thin, and ZFS pool entries after import.
- Keep Ceph OSD lifecycle and DB/WAL placement in Ansible.
- Do not duplicate Ceph RBD/CephFS storage entries unless live Proxmox storage
  definitions have been inventoried and imported.
- A future `terraform/infra/live/common/proxmox-storage` stack should start as
  catalog/import-only.

When not to move:

- Do not use Terraform to orchestrate Optane DB/WAL migration or OSD recreation.
  Those are maintenance workflows with health gates, not steady-state API
  declarations.

## 7. Node Config, APT Repositories, and Host Basics

Status: node API metadata adopted with BPG; host basics remain Ansible-owned.

Current coverage:

- Host basics are in Ansible:
  - `ansible/lae.proxmox/playbooks/stage2-host-configuration.yml`
  - roles for `common`, `sysctl`, `ssh_config`, `journald`, `fstrim`,
    `swappiness`, `ssh_keys`, `host_limits`, `snmpd`, `node_exporter`
- Proxmox cluster/repo/Ceph repo settings are present in
  `ansible/lae.proxmox/playbooks/group_vars/pve.yml`.
- Current BPG coverage:
  - `terraform/infra/live/common/proxmox-node-basics`
  - imports `pve01`, `pve02`, and `pve03` node config metadata
  - writes a node description clarifying the Terraform/Ansible boundary

Recommendation:

- Keep OS packages, systemd units, SSH, sysctl, chrony, journald, FRR, and
  interface files in Ansible.
- Consider BPG node/apt resources only for Proxmox API-backed settings where
  plans are reliable and imports are clean.
- Avoid mixing BPG network bridge/VLAN resources with Ansible-managed
  `/etc/network/interfaces` on the same hosts until there is a deliberate
  migration window.

When not to move:

- Do not use BPG for first-boot/bootstrap host setup. The provider needs a
  functioning Proxmox API, so Ansible remains the right tool from bare host to
  API-ready node.

## Already Covered Outside The 1-7 List

These are already represented with BPG and should remain Terraform-owned:

- SDN zones/VNets/subnets:
  `terraform/infra/live/common/0-sdn-setup`
- PCI/USB hardware mappings:
  `terraform/infra/live/common/proxmox_hardware_mappings`
- Ceph pool declarations:
  `terraform/infra/live/common/2-ceph-pools`
- VM/LXC service modules and test VM modules, with BPG provider updates in
  reusable modules.
- OpenID realm:
  `terraform/infra/live/common/proxmox-realms` adopts the live `idm` realm.

## Suggested Implementation Order

1. Keep `proxmox-access` as the access source of truth and remove account drift
   from Ansible later.
2. Keep HA in BPG and remove the compatibility shims later after any old compute
   state has been audited.
3. Clean up or delete stale guests excluded from Proxmox backups.
4. Roll ACME reissue to `pve01`/`pve02` during a maintenance window if desired.
5. Add `proxmox_metrics_server` only if there is a chosen backend for Proxmox
   push metrics.
6. Leave host bootstrap, network interfaces, FRR, Ceph OSDs, and DB/WAL
   migration in Ansible.
