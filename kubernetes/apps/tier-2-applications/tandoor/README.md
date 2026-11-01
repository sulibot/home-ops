# Tandoor

Tandoor runs at https://tandoor.sulibot.com with its own PostgreSQL database on
postgres-vectorchord and a 5Gi CephFS media volume. Mealie is independent.

## Accounts

Choose **AUTHENTIK** on the login page. The existing Authentik
`policy-access-trusted` policy gates sign-in. New trusted Authentik users are
added to the shared Home / Family household as regular users; no invitation is
needed. The first household operator has Home-space `admin` access for setup and
recipe file imports, without site-wide superuser privileges. Existing accounts
and memberships are not automatically relinked or promoted.

The recovery administrator credentials are in the `tandoor` Login item in the
1Password `Kubernetes` vault. Local account creation is disabled. To connect an
existing local account to Authentik without creating another account, use
**Settings → Account → External Provider → Authentik** while signed in.

Home is initialized with Tandoor's English starter data, including U.S.
customary units and conversions. Configure per-user unit preferences in account
settings.

### Authentication compatibility

Tandoor 2.7.2 uses one `ENABLE_SIGNUP` switch for both local and social signup,
so a small site-specific Django adapter in `app/auth` allows only the configured
Authentik provider to register users while keeping local signup closed. It adds
new users to the configured Home space and Family household by database IDs,
with the `user` role. The Authentik provider's trusted policy is the access gate;
email-based automatic linking is disabled. Missing or mismatched space/household
IDs fail signup instead of granting access elsewhere. Verify these IDs after a
fresh installation; database restores preserve them. Review and test the adapter
against upstream authentication changes whenever upgrading Tandoor. Run the
rollback-only regression check against the deployed pod from the repository root:

```sh
kubectl exec -i -n default deploy/tandoor -- /opt/recipes/venv/bin/python manage.py shell < kubernetes/apps/tier-2-applications/tandoor/tests/auth_regression.py
```

## Recovery

The media volume is backed up by VolSync to Kopia every three hours. Database
backups use the shared CNPG cluster's snapshots and off-cluster WAL/base backups;
restore the database and media together. The fresh-install PVC manifest is excluded
from Kustomize: pre-create it only when there is no backup; for disaster recovery
let VolSync create the PVC from its replication destination.
