# Ticket: Make Kanidm an OIDC source for Authentik

- Status: In Progress
- Priority: Medium
- Area: Kanidm, Authentik, identity
- Created: 2026-07-28

## Summary

Today Kanidm and Authentik are two disconnected identity silos:

- **Kanidm** (`terraform/infra/live/services/kanidm`) is a 3-node HA
  replicated identity server (anycast VIP over BGP, LDAPS on 3636) that
  already backs Proxmox OIDC login and host-level Unix/SSH auth via
  `kanidm-unixd`.
- **Authentik** (`kubernetes/apps/tier-2-applications/authentik`) is the
  app-facing OIDC/proxy broker fronting Grafana, FreshRSS, Vikunja, Immich,
  CloudBeaver, and Cloudflare Access, currently using local accounts + a
  Google OAuth source for login.

Goal: add Kanidm as an OIDC login source in Authentik so a single Kanidm
identity covers both infra (SSH/Proxmox) and app logins, instead of Google
accounts for apps and Kanidm accounts for infra.

**Not in scope: replacing Authentik.** `authentik-outpost`
(`ghcr.io/goauthentik/proxy`) is a forward-auth proxy for apps that don't
speak OIDC/SAML natively — Kanidm has no equivalent, so Authentik stays as
the app-integration layer regardless. This ticket only changes where
Authentik's login identities come from.

## Design

**Kanidm side** (`terraform/infra/live/services/kanidm/main.tf`):
- Install the `kanidm` CLI package on the LXC nodes (already installs
  `kanidmd`).
- New `null_resource.kanidm_oauth2_authentik_client`, gated on `op whoami`
  like the existing `kanidm_1password_sync` resource (skips cleanly if
  1Password isn't authenticated):
  - `kanidm system oauth2 create authentik "Authentik SSO" https://auth.sulibot.com`
  - `kanidm system oauth2 add-redirect-url authentik https://auth.sulibot.com/source/oauth/callback/kanidm/`
  - `kanidm system oauth2 update-scope-map authentik idm_all_persons openid email profile`
  - `kanidm system oauth2 show-basic-secret authentik` → write `client_id`
    (`authentik`) and secret into the 1Password `authentik` item as
    `KANIDM_OIDC_CLIENT_ID` / `KANIDM_OIDC_CLIENT_SECRET`.

**Authentik side** (`kubernetes/apps/tier-2-applications/authentik/app`):
- `blueprints/kanidm-source.yaml`: generic OIDC `oauthsource` (slug
  `kanidm`) pointed at Kanidm's per-client endpoints:
  - `authorization_url`: `https://idm.sulibot.com/ui/oauth2`
  - `access_token_url`: `https://idm.sulibot.com/oauth2/token`
  - `profile_url`: `https://idm.sulibot.com/oauth2/openid/authentik/userinfo`
  - `oidc_jwks_url`: `https://idm.sulibot.com/oauth2/openid/authentik/public_key.jwk`
  - `pkce`: `S256` (required by the Kanidm OAuth2 client)
  - `consumer_key`/`consumer_secret`: `!Env KANIDM_OIDC_CLIENT_ID` /
    `!Env KANIDM_OIDC_CLIENT_SECRET`
- `externalsecret.yaml`: add `KANIDM_OIDC_CLIENT_ID` /
  `KANIDM_OIDC_CLIENT_SECRET` from the `authentik` 1Password item, same
  pattern as every other provider/source.
- `blueprints/host-auth-flows.yaml`: add the Kanidm source to
  `sulibot-shared-auth-identification` alongside Google (additive, not a
  replacement — removing Google is a separate follow-up decision, not made
  here to avoid an unreviewed change to who can log in).

## Acceptance criteria

- [ ] Kanidm has an `authentik` OAuth2 resource server with `openid email
      profile` scopes mapped to `idm_all_persons`.
- [ ] `KANIDM_OIDC_CLIENT_ID`/`SECRET` present in the `authentik` 1Password
      item and flowing through the ExternalSecret.
- [ ] Authentik login screen shows a "Kanidm" source button alongside
      Google, and a Kanidm login successfully authenticates into an
      Authentik-fronted app (e.g. Grafana).
- [ ] `terraform plan`/`apply` clean on `live/services/kanidm`;
      `kubectl kustomize` builds clean on the authentik app.

## Follow-ups (not this ticket)

- Decide whether to retire the Google source once Kanidm login is verified.
- Consider Kanidm groups → Authentik group sync for per-app access policies
  (currently per-app access, e.g. `policy-access-freshrss`, is expression-based).

## Evaluated and rejected (for now): SeanLatimer/kanidm Terraform provider

[`registry.terraform.io/providers/SeanLatimer/kanidm`](https://registry.terraform.io/providers/SeanLatimer/kanidm)
has a `kanidm_oauth2_basic` resource whose docs show an example matching
this exact use case (Authentik redirect URI, scope map). Rejected for this
round: created 2026-05-27, last commit 2026-05-31 (stale ~2 months), 1
star/1 fork, single maintainer, unverified on the registry, and its recent
commit history is mostly state-drift/empty-string bug fixes — not enough
of a track record to manage state against a live production IdP yet.
Went with `kanidm` CLI over SSH instead, matching this repo's existing
convention (the `zot-lxc` stack's Kanidm OIDC client was created the same
way). **Worth revisiting later** if the provider matures (more stars,
sustained commits, a stable 0.x/1.0) — declarative `kanidm_oauth2_basic`
resources would be a real improvement over hand-rolled CLI scripting for
every future Kanidm-backed app (there will be more of these as more apps
get Kanidm-native OIDC clients instead of going through Authentik).
