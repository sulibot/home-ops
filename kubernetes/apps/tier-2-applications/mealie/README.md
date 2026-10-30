# Mealie

Household recipes, meal plans, and shopping lists at https://mealie.sulibot.com.

Uses the shared bjw-s-labs app-template 4.6.2 chart, pinned Mealie v3.29.0,
`postgres-vectorchord` with its own `mealie` database/login role, and a 5Gi
CephFS asset volume. PostgreSQL data stays on the existing database cluster;
SQLite is not used on CephFS.

## Credentials and first login

Open the `mealie` Login item in the 1Password `Kubernetes` vault. Its login
password replaces the vendor bootstrap password. Signups are disabled.
The initial email is Mealie's vendor placeholder; change it and the display
name in the profile after first login, then update the saved 1Password login.
Invite the second cook into the existing `Family` household in the `Home`
group so recipes, plans, and shopping lists are shared. SMTP is not configured;
use a copied invitation link. Do not create a separate household for the partner.

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
