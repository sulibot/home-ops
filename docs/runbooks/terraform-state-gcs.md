# Terraform state GCS operations

## Authority and scope

The authoritative Terraform/OpenTofu/Terragrunt state backend is:

- project: `sulibot-openbao-kms`;
- bucket: `sulibot-terraform-state`;
- location and class: regional `US-CENTRAL1`, `STANDARD`;
- object mapping: `<path_relative_to_include()>/default.tfstate`;
- backend identity:
  `terraform-state@sulibot-openbao-kms.iam.gserviceaccount.com`.

`terraform/infra/root.hcl` configures this backend for every active Terragrunt
unit. The disabled `live/artifacts/extension` placeholder has no Terraform
source and is intentionally not a state-bearing unit.

The exact post-migration unit, lineage, serial, resource count, byte count, and
SHA-256 inventory is in `terraform-state-gcs-inventory.tsv`. It contains 47
authoritative objects: 46 migrated states and one empty state for the
not-yet-applied `live/services/tailscale-config` unit.

## Security controls

- uniform bucket-level access;
- enforced public-access prevention;
- Google-managed encryption at rest and TLS in transit;
- Object Versioning;
- noncurrent generations retained for 90 days;
- soft-deleted generations retained for 14 days;
- no retention lock;
- bucket and bootstrap-resource deletion protection;
- a bucket-scoped custom backend role containing only bucket-read and
  object read/write/list/delete permissions;
- operator access through ADC and service-account impersonation;
- GitHub Actions access through Workload Identity Federation, restricted to
  repository ID `912241670` and actor ID `6082800`;
- no committed or generated service-account key for the backend identity;
- a separate 1Password-managed backup identity with read-only access;
- independent immutable B2 copies every six hours.

The isolated bootstrap root is `terraform/bootstrap/gcs-state`. Its local state
must remain ignored by Git and have an age-encrypted copy outside the
repository after every bootstrap change.

## Routine operator use

Authenticate with personal ADC. Terragrunt then impersonates the dedicated
backend identity configured in `root.hcl`:

```bash
gcloud auth application-default login
cd terraform/infra/live/<unit>
terragrunt init
terragrunt plan
```

Never pass credentials through `-backend-config`, commit a credential file, or
add access keys to a Terragrunt `remote_state` block.

## Migration record

Migration was performed on 2026-07-29:

1. 46 source states were inventoried by lineage, serial, resource count, and
   SHA-256.
2. A pre-migration archive was encrypted to the repository age recipient and
   decrypt-tested. Archive SHA-256:
   `81a542df1a92b4b71976330b42b85495d2109be71caac2b5bb2f0223a9690896`.
3. The GCS bootstrap created 12 resources, then one read-only backup binding;
   both applies had zero changes or destroys.
   The final decrypt-tested bootstrap-state archive SHA-256 is
   `29ccace450099b1610a5eab4a85077642a2974cf9d372d140a4d544f8cfb6198`.
4. Each source backend was initialized before configuration changed.
5. Every state was migrated individually with `terragrunt init
   -migrate-state -force-copy`.
6. All 46 lineages and resource counts matched after migration. Each state
   serial advanced exactly once when GCS wrote the migrated object.
7. `live/services/tailscale-config` initialized an empty, dedicated state:
   lineage `63e65582-a82c-bcf9-09b0-576e36a44d3d`, serial 1.

The local backend files and Cloudflare MinIO object remain rollback sources
through at least 2026-08-28. They are no longer authoritative and must not
receive writes.

## Verification record and plan gate

Native GCS locking was tested with two concurrent RouterOS plans. The first
created `live/routeros/default.tflock`; the second failed with `Error acquiring
the state lock`; the lock disappeared after the clean holder plan exited.

Prior-generation recovery was tested with
`live/artifacts/schematic/default.tfstate`. Generation
`1785360288069175` was recovered to a restricted local file. The recovered
SHA-256, lineage, serial, and resource count matched the source:

```text
sha256    8da954c74352db57544dbb1c006cd0a69c561e779135574002e3d0ef6dbc98c3
lineage   4ea36775-c5cd-db1c-9ac5-92bbe7e4e243
serial    3
resources 1
```

Post-migration plans produced:

- 25 clean plans;
- 15 plans with pre-existing configuration drift;
- 6 plans blocked by existing catalog hooks or configuration prerequisites.

No drift plan was applied. Most replace actions affect `null_resource`
provisioning triggers. `live/services/nixfs-lxc` is the important exception:
the current `main` configuration omits an existing `/srv/common` mount point
and plans to replace container `200204`. Do not apply that unit until its
configuration is reconciled with the operator checkout.

Other notable non-destructive drift includes cluster-101 Talos apply-mode
changes and an in-place `nixbuild-vm` refresh. Treat every non-clean plan as a
separate reviewed infrastructure change; it is not part of the backend
migration.

## Generation recovery

Freeze writers before recovery. List generations:

```bash
gcloud storage ls --all-versions --long \
  gs://sulibot-terraform-state/live/<unit>/default.tfstate
```

Recover a selected generation to a local file first:

```bash
umask 077
gcloud storage cp \
  'gs://sulibot-terraform-state/live/<unit>/default.tfstate#<generation>' \
  ./recovered.tfstate
jq '{lineage, serial, resources: (.resources | length)}' recovered.tfstate
```

Compare it with `terragrunt state pull` and the inventory. Only after peer
review should it be restored with `terragrunt state push`. Never use
`-force` to bypass a lineage or newer-serial rejection without a separately
verified recovery copy.

## Break-glass access

If service-account impersonation is unavailable:

1. freeze all Terraform writers;
2. authenticate the project owner with MFA-protected ADC;
3. use `gcloud storage cp` to recover a selected generation without changing
   the live object;
4. repair the service-account IAM binding through the isolated bootstrap root;
5. verify impersonation and a no-change bootstrap plan;
6. resume normal Terragrunt access.

Do not permanently grant the operator direct object access as a shortcut and
do not create a backend service-account key.

## Independent B2 recovery

`gcs-terraform-state-offsite-copy` runs in `volsync-system` every six hours.
It:

- has no Kubernetes API token;
- mounts the existing 1Password-managed GCS archive credential;
- has read-only access to the GCS state bucket;
- uses the independently scoped B2 infrastructure credential;
- performs `rclone copy`, never `sync` or destination deletion;
- requires at least 47 source state objects;
- verifies that B2 contains at least the same number of current state objects.

The initial job `gcs-terraform-state-offsite-copy-eng350` and final
threshold-validation job `gcs-terraform-state-offsite-copy-eng350-final`
completed on 2026-07-29 and verified all 47 objects in B2. B2 versioning and
Object Lock remain the independent recovery mechanism if GCP is unavailable
or compromised.

To test it manually:

```bash
kubectl -n volsync-system create job \
  --from=cronjob/gcs-terraform-state-offsite-copy \
  gcs-terraform-state-offsite-copy-$(date +%Y%m%d%H%M%S)
```

Restore B2 objects to a quarantine directory or bucket first. Never restore
directly over live GCS state without lineage, serial, resource-address, and
plan verification.
