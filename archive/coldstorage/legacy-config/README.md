# Legacy Config Cold Storage

This directory contains old configuration code that is retained for reference
only. It is not part of the live automation path.

Moved here on 2026-07-07:

- `bootstrap/`: legacy Helmfile/bootstrap manifests.
- `helmvalues/`: legacy hand-maintained Helm values.
- `z_old_terraform/`: superseded Terraform/Terragrunt Proxmox and cluster code.
- `z_old_terraform.disabled/`: older disabled copy of the same generation.

Archived Terragrunt entrypoints are renamed from `terragrunt.hcl` to
`terragrunt.hcl.cold` so recursive Terragrunt discovery does not try to parse or
apply them.

Restore policy:

1. Copy the needed file or directory out of cold storage.
2. Rename any `terragrunt.hcl.cold` file back to `terragrunt.hcl` only in the
   temporary restore location.
3. Review secrets and provider versions before running anything.

Deletion policy:

- Delete after the current BPG/Terraform and Ansible split has been stable long
  enough that no rollback/reference value remains.
- Prefer deleting one top-level directory at a time so review stays obvious.
