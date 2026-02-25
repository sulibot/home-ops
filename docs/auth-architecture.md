# Authentication Architecture

## Overview

Authentication uses **two independent layers** depending on the access path:

| Path | Gate | Identity Provider |
|------|------|-------------------|
| External (internet) | Cloudflare Access | Google OAuth **directly in Cloudflare** |
| Internal (LAN) | Authentik Proxy Outpost or app-native OIDC | Google OAuth via Authentik |

No firewall ports are opened. All external traffic enters via a **Cloudflare Tunnel** — a
persistent outbound connection from `cloudflared` running in the cluster.

---

## Network Gateways

Two Cilium Gateway API gateways are deployed in the `network` namespace:

| Gateway | IP | Purpose |
|---------|-----|---------|
| `gateway-tunnel` | `10.101.250.11` | External-facing apps — Cloudflare tunnel **and** LAN |
| `gateway-internal` | `10.101.250.12` | Internal-only apps — LAN only |

Both IPs are BGP-advertised and covered by a valid Let's Encrypt wildcard certificate
(`*.sulibot.com`). Cloudflared connects to `gateway-tunnel` via its cluster-internal service
(`cilium-gateway-gateway-tunnel.network.svc.cluster.local:443`).

### Apps on gateway-tunnel (external + LAN)

| Hostname | App | Auth pattern |
|----------|-----|-------------|
| `auth.sulibot.com` | Authentik | Direct — Authentik login page |
| `firefly.sulibot.com` | Firefly III | Proxy outpost → header auth |
| `filebrowser.sulibot.com` | FileBrowser Quantum | Proxy outpost → header auth |
| `filestash.sulibot.com` | Filestash | Filestash own login (basic auth) |
| `immich.sulibot.com` | Immich | Native OIDC via Authentik |
| `plex.sulibot.com` | Plex | Plex account (CF Access bypass) |
| `seerr.sulibot.com` | Jellyseerr | Plex/own auth (CF Access bypass) |

### Apps on gateway-internal (LAN only)

Everything else — arr stack, karakeep, paperless, actual, atuin, home-assistant, etc.

---

## Cloudflare Access (External)

### Architecture Decision: CF Access uses Google directly (NOT Authentik as IdP)

**Why**: Keeping Authentik behind CF Access means the IdP itself is never exposed to
unauthenticated internet traffic. Attack surface is limited to Cloudflare's hardened edge.

```
Internet → Cloudflare Edge (Google OAuth) → Tunnel → gateway-tunnel → App
                                                                         ↓ (if proxy outpost app)
                                                              Authentik Proxy Outpost
```

### How CF Access is configured

In Zero Trust → Access → Applications:

| Application | Hostname(s) | Policy | Notes |
|-------------|------------|--------|-------|
| `*.sulibot.com` | `*.sulibot.com` | Allow Google (6 approved emails) | Wildcard catch-all |
| `plex (bypass)` | `plex.sulibot.com` | Bypass | Plex has own account auth |
| `seerr (bypass)` | `seerr.sulibot.com`, `requests.sulibot.com` | Bypass | Jellyseerr own auth |
| `requests (bypass)` | — | Bypass | — |
| `atuin (bypass)` | `atuin.sulibot.com` | Bypass | Atuin uses own token auth |

**Important**: `auth.sulibot.com` is covered by the wildcard app with Google auth — no
special bypass needed. CF validates the Google session before the request reaches Authentik.

**Approved Google accounts** (set in Zero Trust → Access → Access Groups):
- `bcwallace@gmail.com`
- `bodawee@gmail.com`
- `sarah.kalas@gmail.com`
- `munirah.ahmad1@gmail.com`
- `sulaiman.ahmad@gmail.com`
- `sulibot@gmail.com`

### Cloudflare tunnel config

Stored as a Kubernetes Secret (via ExternalSecret from 1Password):
`kubernetes/apps/tier-1-infrastructure/cloudflare-tunnel/app/externalsecret.yaml`

```yaml
ingress:
  - hostname: "*.sulibot.com"
    originRequest:
      http2Origin: true
      noTLSVerify: true        # required: CF sends HTTPS but cluster cert is self-signed from CF's perspective
      originServerName: sulibot.com  # TLS SNI must match the wildcard LE cert CN
    service: https://cilium-gateway-gateway-tunnel.network.svc.cluster.local:443
  - service: http_status:404
```

> `noTLSVerify: true` is set because the cluster's cert is a real LE cert but the Cloudflare
> tunnel can't verify it against the tunnel's internal connection. `originServerName` ensures
> SNI matches so the gateway selects the correct certificate.

---

## Internal (LAN) Access

### LAN DNS Requirements

LAN devices must resolve `*.sulibot.com` subdomains to the correct gateway. Without this,
DNS falls through to Cloudflare's public resolvers which return Cloudflare anycast IPs,
causing `CF Error 1003 — Direct IP access not allowed`.

**Mikrotik DNS static entries required:**

All `gateway-tunnel` apps (accessible externally) must point to `10.101.250.11`:

```
auth.sulibot.com          → 10.101.250.11
firefly.sulibot.com       → 10.101.250.11
filebrowser.sulibot.com   → 10.101.250.11
filestash.sulibot.com     → 10.101.250.11
immich.sulibot.com        → 10.101.250.11
plex.sulibot.com          → 10.101.250.11
seerr.sulibot.com         → 10.101.250.11
```

All `gateway-internal` apps use `10.101.250.12`. A wildcard `*.sulibot.com → 10.101.250.12`
covers the default case; specific entries above override for tunnel apps.

> On LAN, CF Access is bypassed entirely — requests go straight to the Cilium gateway.
> Authentik handles authentication directly using Google OAuth (browser → Google → Authentik).

---

## Authentik

Authentik runs at `https://auth.sulibot.com`. It is deployed via:
`kubernetes/apps/tier-2-applications/authentik/`

### Authentik Blueprints (GitOps)

Blueprints live in `blueprints/` (inline ConfigMap) and are auto-instantiated on Authentik
worker startup. They are idempotent — safe to re-apply.

| Blueprint file | Purpose |
|----------------|---------|
| `google-source.yaml` | Google OAuth source + silent enrollment flow |
| `proxy-providers.yaml` | Proxy providers + outpost for firefly/filebrowser/home-assistant |
| `immich-provider.yaml` | OIDC provider for Immich |
| `cloudflare-access.yaml` | OIDC provider for Cloudflare Access (now unused — CF uses Google directly) |
| `karakeep-provider.yaml` | OIDC provider for Karakeep |
| `paperless-provider.yaml` | OIDC provider for Paperless-ngx |
| `actual-provider.yaml` | OIDC provider for Actual Budget |

### Silent Enrollment Flow (Google OAuth → Authentik user)

When a user logs in via Google OAuth for the first time, Authentik runs `source-enrollment-silent`:

1. **ExpressionPolicy** `source-enrollment-set-username` runs **before** UserWriteStage
   - Derives `username` from the Google `email` field
   - Required because Google OAuth returns `email`+`name` but NOT `username`
   - Import path (Authentik 2025.x+): `from authentik.stages.prompt.stage import PLAN_CONTEXT_PROMPT`
2. **UserWriteStage** creates the user account
3. **UserLoginStage** logs them in

**Known gotcha**: `PLAN_CONTEXT_PROMPT` moved from `authentik.flows.planner` to
`authentik.stages.prompt.stage` in Authentik 2025.x. If the import fails, the enrollment
fails with `"Aborting write to empty username"` → user sees `"Request has been denied"`.

### Authentication flow (default-authentication-flow)

The default authentication identification stage is configured to **only show Google OAuth**
(no password fields). `user_fields: []` + `sources: [google]`. This means:
- Internal LAN users see "Login with Google" → Google OAuth → back to Authentik
- No password login option (by design)

### 1Password secrets (item: `authentik`, vault: Kubernetes)

| Field | Description |
|-------|-------------|
| `POSTGRESQL__USER` | PostgreSQL username |
| `POSTGRESQL__PASSWORD` | PostgreSQL password |
| `SECRET_KEY` | Authentik secret key (random 50+ chars) |
| `EMAIL__HOST` | SMTP host |
| `EMAIL__USERNAME` | SMTP username |
| `EMAIL__PASSWORD` | SMTP password |
| `EMAIL__FROM` | From address for Authentik emails |
| `GOOGLE_CLIENT_ID` | Google OAuth2 client ID (for Authentik Google source) |
| `GOOGLE_CLIENT_SECRET` | Google OAuth2 client secret |
| `IMMICH_OIDC_CLIENT_ID` | e.g. `immich` |
| `IMMICH_OIDC_CLIENT_SECRET` | random |
| `KARAKEEP_OIDC_CLIENT_ID` | e.g. `karakeep` |
| `KARAKEEP_OIDC_CLIENT_SECRET` | random |
| `PAPERLESS_OIDC_CLIENT_ID` | e.g. `paperless` |
| `PAPERLESS_OIDC_CLIENT_SECRET` | random |
| `ACTUAL_OIDC_CLIENT_ID` | e.g. `actual` |
| `ACTUAL_OIDC_CLIENT_SECRET` | random |
| `OUTPOST_TOKEN` | API token for proxy outpost deployment (random 40+ chars) |
| `CF_ACCESS_CLIENT_ID` | CF Access OIDC client ID (legacy — not used since CF switched to Google directly) |
| `CF_ACCESS_CLIENT_SECRET` | CF Access OIDC secret (legacy) |
| `CF_ACCESS_CALLBACK_URL` | CF Access callback URL (legacy) |

Also needs from item `cloudnative-pg-superuser`:
- `POSTGRES_SUPER_PASS` — used by `postgres-init` init container to create the DB

---

## App Auth Patterns

### Pattern 1: Authentik Proxy Outpost (header injection)

Apps: **Firefly III**, **FileBrowser Quantum**, **Home Assistant**

The HTTPRoute sends ALL traffic to `authentik-outpost:9000` (not directly to the app).

```
Browser → filebrowser.sulibot.com
    → gateway-tunnel
    → authentik-outpost:9000
        [no session] → redirect to auth.sulibot.com/application/o/authorize/...
                         → Google login → Authentik session created
                         → callback to filebrowser.sulibot.com/outpost.goauthentik.io/callback
        [session valid] → proxy to internal_host with injected headers
    → App receives X-Authentik-Email, X-Authentik-Username, etc.
```

**Outpost deployment**: `kubernetes/apps/tier-2-applications/authentik-outpost/`
**Outpost HelmRelease env vars:**
- `AUTHENTIK_HOST` — internal API URL: `http://authentik-server.default.svc.cluster.local`
- `AUTHENTIK_HOST_BROWSER` — browser redirect URL: `https://auth.sulibot.com`
- `AUTHENTIK_INSECURE` — `false`
- `AUTHENTIK_TOKEN` — from `authentik-outpost-secret` (ExternalSecret → 1Password `OUTPOST_TOKEN`)

**Proxy providers** (in `proxy-providers.yaml` blueprint):

| App | external_host | internal_host |
|-----|--------------|--------------|
| filebrowser-proxy | `https://filebrowser.sulibot.com` | `http://filebrowser.default.svc.cluster.local:80` |
| firefly-proxy | `https://firefly.sulibot.com` | `http://firefly-app.default.svc.cluster.local:8080` |
| home-assistant-proxy | `https://home-assistant.sulibot.com` | `http://home-assistant.default.svc.cluster.local:8123` |

**Firefly III header auth**: Reads `HTTP_X_AUTHENTIK_EMAIL` via `AUTHENTICATION_GUARD=remote_user_guard`.
Auto-creates users on first login.

**FileBrowser Quantum proxy auth**: Reads `X-authentik-email` header.
`createUser: true` in config.yaml — auto-creates users on first login.
Database path **must** be set via `server.database` in config.yaml (the `FILEBROWSER_DATABASE`
env var is silently ignored by this image).

**Home Assistant**: Shows its own login screen after the outpost auth gate. For seamless SSO,
add to `/config/configuration.yaml`:
```yaml
homeassistant:
  auth_providers:
    - type: trusted_networks
      trusted_networks:
        - fd00:42::/32   # cluster pod CIDR (adjust to your pod network)
      allow_bypass_login: true
    - type: homeassistant
```

### Pattern 2: Native OIDC (app initiates OIDC against Authentik)

Apps: **Immich**, **Paperless-ngx**, **Karakeep**, **Actual Budget**

The app redirects users to Authentik for login. Users authenticate with Google via Authentik.
Accounts are auto-created on first login.

| App | Authentik issuer URL | Blueprint |
|-----|---------------------|-----------|
| Immich | `https://auth.sulibot.com/application/o/immich/` | `immich-provider.yaml` |
| Paperless-ngx | `https://auth.sulibot.com/application/o/paperless/` | `paperless-provider.yaml` |
| Karakeep | `https://auth.sulibot.com/application/o/karakeep/` | `karakeep-provider.yaml` |
| Actual Budget | `https://auth.sulibot.com/application/o/actual/` | `actual-provider.yaml` |

Client ID and secret are injected via ExternalSecret from 1Password into `authentik-secret`,
then read into the app via the app's own ExternalSecret.

### Pattern 3: CF Access bypass + own auth (passthrough)

Apps: **Plex**, **Seerr/Jellyseerr**, **Atuin**

These apps have CF Access Bypass applications in Zero Trust, so they reach the cluster
without a Google login gate. They use their own authentication:
- Plex → Plex account
- Seerr → Plex account or local user
- Atuin → Atuin token

### Pattern 4: Basic auth / API key (LAN only, gateway-internal)

Apps: Radarr, Sonarr, qBittorrent, NZBGet, etc.

Accessible only on LAN via `gateway-internal` (10.101.250.12). Not exposed externally.
Use their own API keys or basic auth.

### Pattern 5: Filestash (direct, own login)

Filestash is on `gateway-tunnel` (externally accessible via CF Access Google gate) but
has its own admin login — OIDC is enterprise-only in the AGPL edition.
Admin password is in 1Password item `filestash` → `ADMIN_PASSWORD` (bcrypt hash).

---

## Adding a New App: Checklist

### New app with proxy outpost auth (header injection)

1. Add the proxy provider + application to `proxy-providers.yaml` blueprint
2. Add the provider to the outpost's `providers:` list in the same blueprint
3. In the app's HelmRelease, point the HTTPRoute `backendRefs` to `authentik-outpost:9000`
4. Configure the app to trust the header (e.g. `AUTHENTICATION_GUARD=remote_user_guard`)
5. If internal LAN access needed: add DNS entry in Mikrotik → `10.101.250.11`

### New app with native OIDC

1. Add the OIDC provider + application to a new blueprint file in `blueprints/`
2. Add the blueprint filename to the ConfigMap in `blueprintconfigmap.yaml`
3. Add `CLIENT_ID` and `CLIENT_SECRET` fields to the `authentik` 1Password item
4. Add an ExternalSecret for the app that reads those fields
5. Configure the app's OIDC settings to point to `https://auth.sulibot.com/application/o/<slug>/`
6. If accessible externally: add CF Access application (or ensure `*.sulibot.com` covers it)
7. If internal LAN access needed: add DNS entry in Mikrotik

---

## Troubleshooting

### CF Error 1003 "Direct IP access not allowed"

**Cause**: LAN DNS is resolving a `gateway-tunnel` hostname to Cloudflare's public IP instead
of the local gateway IP `10.101.250.11`.

**Fix**: Add a static DNS entry in Mikrotik: `<subdomain>.sulibot.com → 10.101.250.11`

### Authentik "Request has been denied" on first Google login

**Cause 1**: The enrollment flow's ExpressionPolicy import path is wrong.
Authentik 2025.x+ uses:
`from authentik.stages.prompt.stage import PLAN_CONTEXT_PROMPT`
(old: `from authentik.flows.planner import PLAN_CONTEXT_PROMPT` — fails in 2025.x)

**Fix**: Check the `source-enrollment-set-username` ExpressionPolicy in Authentik admin:
Flows → Policies → `source-enrollment-set-username` → Expression.

**Cause 2**: The `enrollment_flow` on the Google OAuth source is `None`.
This happens if the blueprint runs before the flow is created (ordering bug).

**Fix**: In Authentik Django shell:
```python
from authentik.sources.oauth.models import OAuthSource
from authentik.flows.models import Flow
source = OAuthSource.objects.get(slug='google')
source.enrollment_flow = Flow.objects.get(slug='source-enrollment-silent')
source.save()
```

### Proxy outpost redirecting to `http://authentik-server.default.svc.cluster.local`

**Cause**: `AUTHENTIK_HOST_BROWSER` not set on the outpost deployment.
The outpost uses `AUTHENTIK_HOST` for both internal API calls AND browser redirects.

**Fix**: Set `AUTHENTIK_HOST_BROWSER: "https://auth.sulibot.com"` in the outpost HelmRelease env.

### Filebrowser shows login form instead of auto-logging in (proxy auth fails)

**Cause 1**: `createUser: false` (default) — user doesn't exist in the DB yet.
**Fix**: Ensure `proxy.createUser: true` in `filebrowser-config` ConfigMap.

**Cause 2**: Database not persisted — DB in ephemeral `/home/filebrowser/database.db`.
The `FILEBROWSER_DATABASE` env var is silently ignored by FileBrowser Quantum.
**Fix**: Set `server.database: /config/database.db` in config.yaml (the ConfigMap).

### Authentik outpost 502 Bad Gateway when serving app

**Cause**: `internal_host` in the proxy provider points to the wrong port.
Example: `http://filebrowser.default.svc.cluster.local:80` but service has `targetPort: 8080`.

**Fix**: Match `internal_host` port to the Kubernetes service port (not the container port).
For FileBrowser Quantum: container listens on **port 80** regardless of `FILEBROWSER_PORT` env.
Service and proxy provider should both use port 80.

---

## Files Reference

| File | Purpose |
|------|---------|
| `kubernetes/apps/tier-1-infrastructure/cloudflare-tunnel/app/externalsecret.yaml` | CF tunnel config (ingress rules, TLS settings) |
| `kubernetes/apps/tier-2-applications/authentik/app/helmrelease.yaml` | Authentik HelmRelease |
| `kubernetes/apps/tier-2-applications/authentik/app/blueprintconfigmap.yaml` | All Authentik blueprints (ConfigMap) |
| `kubernetes/apps/tier-2-applications/authentik/app/blueprints/` | Blueprint YAML files (baked into ConfigMap) |
| `kubernetes/apps/tier-2-applications/authentik-outpost/app/helmrelease.yaml` | Proxy outpost deployment |
| `kubernetes/apps/tier-2-applications/filebrowser/app/configmap.yaml` | FileBrowser Quantum config (DB path, auth methods) |
