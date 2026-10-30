# Mealie

Household recipes, meal plans, and shopping lists at https://mealie.sulibot.com.

Uses the shared bjw-s-labs app-template 4.6.2 chart, pinned Mealie v3.29.0,
`postgres-vectorchord` with its own `mealie` database/login role, and a 5Gi
CephFS asset volume. PostgreSQL data stays on the existing database cluster;
SQLite is not used on CephFS.

## Credentials and first login

Choose **Sign in with Authentik**. The existing `trusted-users` group and
`policy-access-trusted` gate access; no group memberships are changed. First
SSO login creates a regular Mealie account in `Home` / `Family`, so both cooks
share the same household. No OIDC group automatically grants site administration.
Public password registration is disabled.

Recovery/site administration uses the `mealie` Login item in the 1Password
`Kubernetes` vault. Its password replaces the vendor bootstrap password. The
recovery email remains Mealie's vendor placeholder; it can be changed in the
profile, with the saved 1Password username updated to match. SMTP is not
configured. If another user needs an invitation, copy its link.

The Authentik provider uses a dedicated confidential client, PKCE, standard
openid/profile/email scopes and the groups claim, with strict `/login` and
`/login?direct=1` redirect URIs. Authentik's built-in email mapping returns
`email_verified=false`, so Mealie's email verification requirement is disabled
only for this integration; both provider policy and Mealie require the existing
trusted group. Keep that group's membership and email identities administrator
controlled. Recovery password authentication stays enabled.

U.S. English cooking units are seeded. New recipes default to private.
Safari on iPhone can open the site directly or add it to the Home Screen.

## Secrets

ExternalSecrets read the `mealie` item through `onepassword-connect`:

- `POSTGRES_PASSWORD` supplies `mealie-pg-password` for CNPG and the app.
- Login `username` and `password` supply `mealie-bootstrap` for bootstrap and
  operator verification. They are not injected as unsupported DEFAULT_PASSWORD
  environment variables. Mealie v3.29.0 hardcodes its initial bootstrap login.

For a completely fresh database, keep ingress closed until the vendor bootstrap
password is rotated through localhost to the value saved in 1Password. An
existing database preserves user accounts during redeployment/restoration.

## Storage and recovery

The shared VolSync component backs up `mealie-config` to Kopia every three hours
in its dedicated cron slot. The shared CNPG cluster supplies database snapshots
and off-cluster WAL/base backups. Restore PostgreSQL and assets together.
Mealie's own downloadable application backups provide an additional export.

For a first-ever installation with no backup, pre-create the PVC using
`app/manual-pvc-mealie-config.yaml`. The shared component's IfNotPresent policy
preserves that bound claim; it must not be patched with an immutable restore
source. During disaster recovery, let the shared component create the claim
with its ReplicationDestination source instead.

`API_HOST: "::"` is required because this cluster's primary pod/service addresses
are IPv6. HTTPS uses the existing internal and tunnel gateways and TLS setup.
