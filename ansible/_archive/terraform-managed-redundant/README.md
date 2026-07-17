# Archived: roles redundant with already-live Terraform

Archived 2026-07-14 during the lae.proxmox refactor
(`.claude/plans/declarative-forging-volcano.md`), after discovering both of
these duplicate state that Terraform already manages live.

## pve_accounts

`terraform/infra/live/common/proxmox-access` (module
`terraform/infra/modules/proxmox_access`) already manages exactly the
`Terraform` PVE role, `terraform@pve` user, root ACL, and `provider` API
token that `pve_roles`/`pve_users`/`pve_acls`/`pve_tokens` in
`ansible/pve/inventory/group_vars/pve.yml` (inherited unmodified from the
old lae.proxmox tree) and this role were also about to manage - same
`role_id`, same `user_id`, same ACL path, sourced from a properly
SOPS-encrypted secret rather than the plaintext `password: "TempPass123!"`
that was sitting in the ansible vars. Running this role would have created
a second, competing definition of the same Proxmox objects via the API.

## proxmox_oidc

`terraform/infra/live/common/proxmox-realms` (module
`terraform/infra/modules/proxmox_realms`) already manages the exact same
`idm` OpenID realm (`client_id = "proxmox"`,
`issuer_url = "https://idm.sulibot.com/oauth2/openid/proxmox"`) that this
role's `domains.cfg.j2` template and `pve_oidc_*` vars also configured.

## If reviving either of these

Don't just re-enable them - first decide whether Terraform or Ansible
should own PVE accounts/RBAC and OIDC realm config going forward, and
retire the other side. Managing the same Proxmox objects from both tools
is the drift-prone pattern this whole refactor was meant to eliminate.
