# Tandoor

Tandoor runs at https://tandoor.sulibot.com with its own PostgreSQL database on
postgres-vectorchord and a 5Gi CephFS media volume. Mealie is independent.

## Accounts

The recovery administrator credentials are in the `tandoor` Login item in the
1Password `Kubernetes` vault. Public signup is disabled. Authentik is restricted
by the existing `policy-access-trusted` policy. To onboard a cook, sign in with
the recovery account, create an invitation to the intended space with the `user`
role, and have the cook open the invitation and sign in through Authentik. Repeat
for the other cook. Invitation links are credentials; share them privately.
Tandoor also creates a separate personal space for each new social user; select
the shared space after accepting the invitation. No SSO user is automatically
made a shared-space administrator. Configure preferred measurement units in each
user's settings.

## Recovery

The media volume is backed up by VolSync to Kopia every three hours. Database
backups use the shared CNPG cluster's snapshots and off-cluster WAL/base backups;
restore the database and media together. The fresh-install PVC manifest is excluded
from Kustomize: pre-create it only when there is no backup; for disaster recovery
let VolSync create the PVC from its replication destination.
