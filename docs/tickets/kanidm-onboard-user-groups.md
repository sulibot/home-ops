# Ticket: Onboard Kanidm users by group membership alone

- Status: In Progress
- Priority: Medium
- Area: Kanidm, Authentik, identity
- Created: 2026-07-30

## Summary

Goal: creating a Kanidm person and putting them in the right group(s) should
be the entire onboarding step. No Terraform/Terragrunt involvement in person
or group *membership* lifecycle - that stays a `kanidm` CLI/API concern (see
"Evaluated and rejected" in `docs/tickets/kanidm-oidc-source-for-authentik.md`
for why a Terraform provider isn't used for this either).

Terragrunt's job stays limited to what it already does: wiring hosts/apps to
consume Kanidm as an identity source (unixd config, OIDC clients, scope
maps). It does not create or delete people.

## What "add to group, done" already gets you today

- **Unix/SSH login** on any host provisioned via
  `terraform/infra/live/common/lxc-kanidm-auth.hcl` (`kanidm-unixd` +
  `pam_allowed_login_groups`): membership in the configured login group is
  sufficient. Today that's the single flat `posix_group` for every host
  (ENG-349 tracks replacing this with host-class-specific groups).
- **OpenBao**: membership in `openbao-admins` or `openbao-readers` maps
  directly to Vault policy via Kanidm's own OIDC client and scope map
  (`terraform/infra/live/services/openbao/configure-kanidm-oidc.sh`).
- **Proxmox**: already OIDC-backed by Kanidm (per
  `docs/tickets/kanidm-oidc-source-for-authentik.md`); group->ACL mapping
  is the still-open part of ENG-349, not implemented yet.
- **OpenCloud**: dedicated `opencloud-users` / `opencloud-admins` groups
  already control access (ENG-347).

## What this ticket adds: Authentik-fronted apps

Authentik-fronted apps (Grafana, FreshRSS, Vikunja, Immich, CloudBeaver,
Cloudflare Access, ...) previously required a *second*, disconnected step:
manually adding the person to an Authentik-local group
(`standard-users`/`trusted-users`/`infrastructure-users`, see
`kubernetes/apps/tier-2-applications/authentik/app/blueprints/authorization-groups.yaml`)
independent of anything in Kanidm.

Fix, in two parts:

1. **Kanidm side (done, `terraform/infra/live/services/kanidm/terragrunt.hcl`,
   `null_resource.kanidm_oauth2_authentik_client`)**: grant the `groups_name`
   scope on the `authentik` OAuth2 client's `idm_all_persons` scope map, so
   the token Authentik receives on Kanidm login includes a `groups` claim
   listing the person's Kanidm group names.
2. **Authentik side (not yet done - see below)**: Authentik has supported
   automatic OAuth-source group sync from a `groups` claim natively since
   v2024.8 (deployed version here: 2026.2.0). Kanidm isn't one of the
   "known" providers (Google/GitHub/etc.) that ship a default group
   property mapping, so the Kanidm source
   (`blueprints/kanidm-source.yaml`) needs an explicit custom
   `authentik_sources_oauth.oauthsourcepropertymapping`-style group
   mapping attached to it. The exact model/field names need to be
   confirmed against the live Authentik 2026.2.0 blueprint schema (e.g. via
   its browsable API schema, or by configuring it once through the UI and
   exporting the resulting blueprint) before committing YAML for this,
   since a malformed source blueprint applies against a production
   identity broker fronting every app behind it.

## User tiers

Three human tiers, deliberately reusing the Authentik group names that
already exist (`authorization-groups.yaml`) so the groups-claim sync (above)
lines up 1:1 with no renaming:

| Tier | Who | Kanidm groups |
|---|---|---|
| `tier-admin` | infra admin (you) | `posix_group`, `infrastructure-users`, `trusted-users`, `standard-users`, `openbao-admins`, `opencloud-admins` |
| `tier-trusted` | wife, family member: finance app, CloudBeaver, Filebrowser, secured shares | `trusted-users`, `standard-users`, `opencloud-users` |
| `tier-standard` | friend: consumer apps only, can't break anything | `standard-users`, `opencloud-users` - no `posix_group` (no SSH), no OpenBao, no admin group anywhere |

Confirmed 2026-07-30: `trusted-users` vs `standard-users` today materially
means CloudBeaver (raw SQL) + Filebrowser (raw filesystem) access - every
other app's access policy accepts either group. **Fixed as part of this
ticket**: both finance apps were bound to `policy-access-standard`, which
both tiers satisfy - re-bound to `policy-access-trusted` so `tier-standard`
(friend) does not get finance access:
- `actual-provider.yaml` (Actual Budget)
- `proxy-providers.yaml`'s `firefly` application binding (Firefly III) -
  this file bundles several apps (firefly, grimmory, digarr, aurral,
  home-assistant-app) behind shared forward-auth proxies; only firefly's
  binding was changed, the others are unrelated to finance and left as-is.

Both validated with `kubectl kustomize`; not yet applied to the live
cluster.

**Open**: "secured drives/shares" for `tier-trusted` has no backing
mechanism yet. `docs/architecture/user-storage-identity-and-sync.md` is
explicitly "initial single-user implementation (`sulibot`)" - there is no
existing multi-user share/permission model to grant a second person
(wife, family member) a restricted storage area today. This needs its own design, not
just a group name, before `tier-trusted` can actually deliver it.

Machines/services are explicitly **not** a fourth human tier - Kanidm
separates person accounts from service accounts as first-class types
(https://kanidm.github.io/kanidm/stable/accounts/intro.html), and per
ENG-349, machine identities stay out of human groups entirely. A service
gets its own `kanidm service-account create` object and a `svc-<app>`
group / dedicated OIDC client, mirroring the pattern OpenBao/Proxmox
already use - never `posix_group` or `standard-users`.

Kanidm also supports nested groups
(https://kanidm.github.io/kanidm/stable/accounts/groups.html), so
`tier-admin`/`tier-trusted` could nest inside `standard-users` instead of
every admin needing separate membership - worth doing once the tiers
above are confirmed, to avoid drift between them.

## Onboarding: executes by default, `--dry-run` to just print

`terraform/infra/live/services/kanidm/onboard-user.sh <username>
"<display name>" <tier> [gidnumber] [--dry-run]`. Always prints the exact
`kanidm` command sequence for the given tier before doing anything; by
default it then runs those commands over SSH against a Kanidm node
(logging in as `idm_admin` using the password from the 1Password `kanidm`
item). Pass `--dry-run` to only see the plan without executing it.
Credential recovery (`kanidmd ... scripting recover-account`) is
deliberately left as a separate, manual step since it prints a one-time
secret that needs its own handling.

## Acceptance criteria

- [X] Kanidm's `authentik` OAuth2 client emits a `groups` claim.
- [X] Onboarding for infra access (SSH, OpenBao, OpenCloud) resolves to a
      visible, printed command sequence keyed by tier, not a black-box
      script.
- [ ] Confirm the three tiers above (naming, group membership) before
      relying on them further.
- [ ] Nest `tier-admin`/`tier-trusted` inside `standard-users` instead of
      flat per-tier membership lists, once confirmed.
- [ ] Service-account command set (mirroring `onboard-commands.sh` but for
      `kanidm service-account create` + `svc-<app>` groups) - not started.
- [ ] Authentik's Kanidm source syncs the `groups` claim into Authentik
      groups automatically (needs the schema verification noted above).
- [ ] At least one Authentik-fronted app's access policy is bound to a
      Kanidm-sourced group instead of a manually-maintained Authentik-local
      one, as a proof of the end-to-end path.
