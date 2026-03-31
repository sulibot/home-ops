# Baserow and n8n Auth Operations

## Current State

### Local admin accounts

The local admin-capable accounts have already been created and verified.

| App | Login | Privilege level | Display name | 1Password item |
|-----|-------|-----------------|--------------|----------------|
| Baserow | `admin@sulibot.com` | staff admin | `Sulaiman Admin` | `baserow-admin` |
| Baserow | `sulibot@gmail.com` | staff admin | `Sulaiman Admin` | `baserow-sulibot` |
| n8n | `admin@sulibot.com` | global owner | `Sulaiman Admin` | `n8n-admin` |
| n8n | `sulibot@gmail.com` | global admin | `Sulaiman Admin` | `n8n-sulibot` |

These credentials are stored in the `Kubernetes` vault in 1Password and are intended to remain available as local admin and break-glass accounts even if SSO is added later.

### Runtime secrets

The runtime app secrets remain separate:

| App | 1Password item | Purpose |
|-----|----------------|---------|
| Baserow | `baserow` | database password, app secret key |
| n8n | `n8n` | database password, encryption key |

The admin login credentials are not synced into Kubernetes Secrets because the applications do not need them at runtime.

### Account model

The intended steady state is:

- `admin@sulibot.com` remains the primary break-glass admin account
- `sulibot@gmail.com` is the normal secondary human admin account
- neither account should be removed when adding SSO until API and UI auth have both been re-validated

## OIDC Status

### n8n

OIDC is not currently enabled.

The running instance reports:

- `showSetupOnFirstLoad: false`
- `enterprise.oidc: false`
- `sso.oidc.loginEnabled: false`

That means local owner login is active and working, but OIDC cannot be enabled in the current edition without additional product capability or licensing.

### Baserow

OIDC is not currently enabled.

The first local admin account exists and should be kept in place as the bootstrap and break-glass account before any future SSO work.

## Hard Requirement

Any future OIDC rollout must not break API access.

This means:

1. Existing API authentication must continue to work after SSO is enabled.
2. A local admin account must remain available until SSO is verified.
3. API clients must use app-native API tokens or API keys, not browser login sessions.

## API-Safe OIDC Rollout Checklist

### Preconditions

Before enabling OIDC on either app:

1. Confirm the product edition actually supports OIDC.
2. Confirm the local bootstrap admin can log in successfully.
3. Create and save at least one API credential before changing auth.
4. Record the pre-change API test results.

### n8n validation

For n8n, API access should rely on API keys, not UI session cookies.

Before OIDC:

```bash
curl -sS https://n8n.sulibot.com/rest/settings | jq '.data.userManagement,.data.enterprise,.data.sso'
```

After an API key is created:

```bash
curl -sS https://n8n.sulibot.com/api/v1/workflows \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}"
```

Success criteria:

- returns `200`
- no dependency on browser cookies
- still works after OIDC is enabled

### Baserow validation

For Baserow, validate token auth and any workspace/database API tokens separately.

Local admin token auth:

```bash
curl -sS -X POST https://baserow.sulibot.com/api/user/token-auth/ \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin@sulibot.com","password":"REDACTED"}'
```

Success criteria:

- returns `200`
- issues JWT tokens successfully
- still works or an equivalent supported API auth path remains available after SSO enablement

### Rollout order

Use this order when OIDC becomes available:

1. Keep local admin enabled.
2. Configure OIDC provider.
3. Test OIDC login with a non-critical user.
4. Re-run API smoke tests.
5. Test existing API clients or automation credentials.
6. Keep local admin as break-glass access unless there is a specific reason to remove it.

## Notes From Initial Bootstrap

- In some products, the first local user must exist before OIDC can be used safely.
- That assumption was treated as a requirement here.
- Both `Baserow` and `n8n` were bootstrapped with local admin accounts first.
