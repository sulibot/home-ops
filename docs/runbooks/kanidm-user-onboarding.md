# Kanidm user onboarding

Design and open work: `docs/architecture/identity-and-authorization-control-plane.md`.
This runbook is the "how do I actually do it" version.

## Tiers

| Tier | Who | What it gets you |
|---|---|---|
| `tier-admin` | infra admin (you) | SSH everywhere, full app admin, OpenBao/OpenCloud admin |
| `tier-trusted` | wife, family member | Finance apps (Actual, Firefly III), CloudBeaver (raw SQL), Filebrowser (raw filesystem). No SSH, no OpenBao, no infra admin. |
| `tier-standard` | friend | Consumer apps only. No SSH, no OpenBao, no admin group, no finance apps. |

Machines/services are never onboarded through this runbook - see "Service
accounts" below.

## Onboard a person

From a machine with 1Password CLI authenticated and SSH access to the
Kanidm nodes:

```
terraform/infra/live/services/kanidm/onboard-user.sh <username> "<display name>" <tier> [gidnumber] [--dry-run]
```

- Always prints the exact `kanidm` command sequence for the tier before
  doing anything.
- Without `--dry-run`, it then runs those commands over SSH against a
  Kanidm node.
- With `--dry-run`, it only prints the plan.

Example - onboarding a family member as `tier-trusted`:

```
terraform/infra/live/services/kanidm/onboard-user.sh jsmith "Jane Smith" tier-trusted --dry-run
```

### After onboarding: recover a credential

The script deliberately does not do this step, since it prints a
one-time secret that needs its own handling:

```
ssh root@10.100.0.61 kanidmd -c /etc/kanidmd/server.toml scripting recover-account '<username>'
```

Hand the resulting password to the person directly, or store it in the
`Kubernetes` 1Password vault under a per-person item (see the pattern in
`terraform/infra/live/services/openbao/configure-kanidm-oidc.sh`).

## Offboarding

Not yet scripted. Remove the person from every group they're in
(`kanidm group remove-members <group> <username> --name idm_admin` per
group), or delete the person outright
(`kanidm person delete <username> --name idm_admin`) if they should lose
access entirely, not just be downgraded.

## Service accounts

Not yet built. Machines/services must never join `posix_group`,
`standard-users`, `trusted-users`, or any other human group - they get
their own Kanidm *service account* (`kanidm service-account create`) and
a dedicated `svc-<app>` group / OIDC client, the same pattern OpenBao and
Proxmox already use for their own clients.

## Known caveats

- Authentik-fronted apps read Authentik-local group membership today, not
  Kanidm group membership directly - the sync between them
  (`groups_name` scope on Kanidm's `authentik` OIDC client -> Authentik
  group sync) is validated but not fully wired up. See ENG-357.
- "Secured drives/shares" for `tier-trusted` has no backing storage
  mechanism yet - only single-user (`sulibot`) storage exists today.
- Double-check any *new* app's Authentik access-policy binding before
  assuming a tier controls it - two finance apps (Actual, Firefly III)
  were found bound to `policy-access-standard` (both tiers) instead of
  `policy-access-trusted` and had to be corrected. Don't assume a new
  app defaults to the right policy.
