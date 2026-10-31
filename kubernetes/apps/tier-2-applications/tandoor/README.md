# Tandoor

Tandoor runs at https://tandoor.sulibot.com with its own PostgreSQL database on
postgres-vectorchord and a 5Gi CephFS media volume. Mealie is independent.

## Accounts

The recovery administrator credentials and two single-use Home-space invitation
links are in the `tandoor` Login item in the 1Password `Kubernetes` vault. Each
invitation expires 30 days after creation. Each cook opens a different invitation,
chooses **LOGIN** on the signup screen, then chooses **AUTHENTIK** and signs in.
The provider is restricted by the existing `policy-access-trusted` policy. Public
signup is disabled, and invitation links must be shared privately.

Tandoor also creates a separate personal space for each new social user; select
Home after accepting the invitation. No SSO user is automatically made a
shared-space administrator. Configure preferred measurement units in each
user's settings. If invitations expire, sign in with the recovery administrator
and create replacement Home invitations with the `user` role.

## Recovery

The media volume is backed up by VolSync to Kopia every three hours. Database
backups use the shared CNPG cluster's snapshots and off-cluster WAL/base backups;
restore the database and media together. The fresh-install PVC manifest is excluded
from Kustomize: pre-create it only when there is no backup; for disaster recovery
let VolSync create the PVC from its replication destination.
