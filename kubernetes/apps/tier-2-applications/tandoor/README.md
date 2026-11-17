# Tandoor

Tandoor runs at https://tandoor.sulibot.com with its own PostgreSQL database on
postgres-vectorchord and a 5Gi CephFS media volume. Mealie is independent.

## Accounts

The recovery administrator credentials and Home-space invitation links are in
the `tandoor` Login item in the 1Password `Kubernetes` vault. The first invitation
has been used; the second remains available until November 30, 2026. A new cook
opens the unused invitation, chooses **LOGIN** on the signup screen, then chooses
**AUTHENTIK** and signs in. The provider is restricted by the existing
`policy-access-trusted` policy. Public signup is disabled, and invitation links
must be shared privately.

The first household operator has Home-space `admin` access for setup and recipe
file imports; this does not grant site-wide superuser privileges. The second
invitation grants the `user` role in the shared Home / Family household. New
social users also receive a personal space; select Home for shared work.

Home is initialized with Tandoor's English starter data, including U.S.
customary units and conversions. Configure any per-user unit preferences in account settings. If an
invitation expires, the Home administrator can create a replacement for the
Family household with the `user` role. To connect an existing local account to
Authentik without creating another account, use **Settings → Account → External
Provider → Authentik** while signed in.

## Recovery

The media volume is backed up by VolSync to Kopia every three hours. Database
backups use the shared CNPG cluster's snapshots and off-cluster WAL/base backups;
restore the database and media together. The fresh-install PVC manifest is excluded
from Kustomize: pre-create it only when there is no backup; for disaster recovery
let VolSync create the PVC from its replication destination.
