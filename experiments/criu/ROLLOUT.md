# Talos runtime canary rollout

The source of truth is in this repository, not a hand-edited node file:

- `talos/extensions/zeropod/`: pinned bootstrap build, CRI TOML, node manager,
  RuntimeClass, certificate, and RBAC manifests.
- `terraform/infra/live/clusters/cluster-101/cluster.hcl`: per-node CRI opt-in,
  currently **solwk03 only**.
- `kubernetes/apps/tier-1-infrastructure/zeropod/ks.yaml`: Flux ownership of the
  manager manifests; experimental rollout is gated by `spec.suspend`.
- `experiments/criu/zeropod/`: disposable cross-node IPv6 TCP restore test.

## Ordering

1. Build/push the amd64 bootstrap image and pin its registry digest in the
   DaemonSet. Never put checkpoint files in the image or registry.
2. Apply the node manager manifests and wait for its bootstrap init and manager
   readiness. This installs only `/var/lib/zeropod`; no host shell or systemd is
   assumed. The default runtime remains `runc`.
3. Run the Terragrunt **config** stage plan/apply to persist generated outputs,
   then the **apply** stage plan/apply. Do not edit generated `talenv.yaml` or
   generated per-node YAML to configure the runtime.
4. Confirm `/etc/cri/conf.d/cri.toml` contains the opt-in `zeropod` handler and
   unchanged `runc` settings. CRI restarts when this configuration changes.
5. Run the disposable test before opting in an application. Check actual CRIU
   success, memory release, process identity after wake, and a repeated cycle.
6. Only then activate Flux reconciliation and per-application enrollment. Flux
   cannot reconcile uncommitted local files: publish the reviewed changes first.

The config generator remains on provider 0.10 to avoid an unrelated migration
of every machine document. The apply provider is 0.12 for Talos 1.14's new
`CRICustomizationConfig`. Empty per-node customization maps retain the existing
generation behavior. The shared Terragrunt region input uses `inputs`, so a saved
plan can be applied without extra positional CLI arguments.

## Canary versus full reconciliation

The apply state still includes the previously retired cp02/cp03 resources, and
other nodes retain old install-image references and retired-node routes. The
initial runtime rollout deliberately targeted only
`talos_machine_configuration_apply.nodes["solwk03"]`. Its reviewed changes were
the new CRI document plus the already-requested upgrade references and routes
for the retired control planes. No other node was applied and no VM was recreated.

Targeting is a temporary canary mechanism, not routine whole-cluster convergence.
Do not mistake its no-change plan for a clean **full** apply-stage plan. Review a
full plan separately before reconciling the remaining nodes/state.

Talos 1.14 no longer supports the old automatic reboot-detection behavior:
`staged_if_needing_reboot` resolves to `auto`. Use explicit `staged` when preparing
a change that must wait for a separately scheduled reboot; do not assume the old
setting prevents disruption. The canary apply restarted CRI without rebooting.

Saved plans contain credentials. Store them in a mode-0700 temporary directory,
never in Git, and delete obsolete plans after use. Re-plan after any source or
state change rather than applying an old saved plan.

## Rollback / removal

Before removing the runtime manager or binaries, move opted-in workloads back to
their original runtime and recreate them normally from durable application data.
Local CRIU memory images are not portable backups. Remove the per-node CRI opt-in
through config/apply only after no Pod uses it. The Flux Kustomization deliberately
disables pruning so an accidental Git deletion does not remove a live runtime.
Delete the manager/RuntimeClass explicitly after the drain. Removing them does
not automatically remove files from `/var/lib/zeropod`; inspect and clean those
only after confirming no shim/checkpoint still depends on them.
