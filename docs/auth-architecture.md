# Authentication Architecture

## Overview

Authentication in this cluster uses two independent layers depending on access path:

| Path | Gate | Identity Provider |
|------|------|-------------------|
| External (internet) | Cloudflare Access | Google OAuth (via Cloudflare) |
| Internal (LAN) | Authentik | Google OAuth (via Authentik) |

No firewall ports are opened. All external traffic enters via a **Cloudflare Tunnel** — a
persistent outbound connection from `cloudflared` running in the cluster.

---

## Network Gateways

Two Cilium Gateway API gateways are deployed in the `network` namespace:

| Gateway | IP | Purpose |
|---------|-----|---------|
| `gateway-tunnel` | `10.101.250.11` / `fd00:101:250::11` | External-facing apps (Cloudflare tunnel + LAN) |
| `gateway-internal` | `10.101.250.12` / `fd00:101:250::12` | Internal-only apps (LAN only) |

Both are BGP-advertised, so LAN DNS resolves all `*.sulibot.com` hostnames to the correct
gateway IP directly. Cloudflared connects to `gateway-tunnel` via its cluster-internal service
name (`cilium-gateway-gateway-tunnel.network.svc.cluster.local:443`).

### Apps on gateway-tunnel (external + LAN)

- `immich.sulibot.com`
- `firefly.sulibot.com`
- `filebrowser.sulibot.com`
- `filestash.sulibot.com`
- `plex.sulibot.com`
- `seerr.sulibot.com` / `requests.sulibot.com`
- `auth.sulibot.com` (Authentik itself)

### Apps on gateway-internal (LAN only)

Everything else — arr stack, karakeep, atuin, gatus, etc.

---

## External Access — Cloudflare

### Flow

```
Internet → Cloudflare Edge → Cloudflare Tunnel → gateway-tunnel → App
```

Cloudflare Access intercepts every request before it reaches the tunnel. Unauthenticated
requests are rejected at Cloudflare's edge — they never reach the cluster.

### Cloudflare tunnel config

A single wildcard entry routes all external traffic through `gateway-tunnel`:

```yaml
ingress:
  - hostname: "*.sulibot.com"
    originRequest:
      http2Origin: true
    service: https://cilium-gateway-gateway-tunnel.network.svc.cluster.local:443
  - service: http_status:404
```

### Cloudflare Access setup (manual — Cloudflare Zero Trust dashboard)

1. **Identity Provider**: Zero Trust → Settings → Authentication → Add → Google OAuth
   - Configure with your Google Cloud OAuth2 client credentials
2. **Access Applications**: Zero Trust → Access → Applications → Add Self-hosted
   - One application per externally-exposed hostname
   - Policy: Allow where Email = `you@gmail.com`
   - Apps to protect: `immich`, `firefly`, `filebrowser`, `filestash`, `seerr`, `auth`
   - Apps with own auth (no CF Access policy needed): `plex`

### Why Cloudflare for the edge

- Maintained and patched by Cloudflare's security team — far faster than self-hosted
- DDoS mitigation, IP reputation filtering, bot protection built in
- Attack surface never reaches the cluster network directly
- Tunnel is outbound-only — no open firewall ports required

---

## Internal Access — Authentik

Authentik runs at `auth.sulibot.com` and acts as a central identity broker for LAN access.
It is deployed via the `authentik` Kustomization in `tier-2-applications`.

### Flow (LAN user)

```
LAN → immich.sulibot.com → gateway-internal/tunnel → Immich
                                                         ↓ (OIDC redirect)
                                              auth.sulibot.com (Authentik)
                                                         ↓
                                              accounts.google.com (Google OAuth)
                                                         ↓
                                              Authentik issues OIDC token → Immich
```

Cloudflare is not involved. The Google OAuth redirect goes directly from the browser
to Google's servers.

### Authentik configuration (GitOps via blueprints)

Blueprints live in
[`kubernetes/apps/tier-2-applications/authentik/app/blueprints/`](../kubernetes/apps/tier-2-applications/authentik/app/blueprints/)
and are auto-instantiated on Authentik startup via the `authentik-blueprints` ConfigMap.

| Blueprint | Purpose |
|-----------|---------|
| `google-source.yaml` | Google OAuth source — enables "Login with Google" on Authentik login page |
| `immich-provider.yaml` | OIDC provider + Application for Immich native SSO |
| `cloudflare-access.yaml` | OIDC provider for Cloudflare Access to use Authentik as IdP (optional) |

### 1Password secrets required (in `authentik` item, Kubernetes vault)

| Field | Description |
|-------|-------------|
| `EMAIL__FROM` | From address for Authentik emails |
| `POSTGRESQL__USER` | PostgreSQL username |
| `POSTGRESQL__PASSWORD` | PostgreSQL password |
| `SECRET_KEY` | Authentik secret key (random, 50+ chars) |
| `GOOGLE_CLIENT_ID` | Google OAuth2 client ID (for Google source) |
| `GOOGLE_CLIENT_SECRET` | Google OAuth2 client secret |
| `IMMICH_OIDC_CLIENT_ID` | OAuth2 client ID for Immich provider (e.g. `immich`) |
| `IMMICH_OIDC_CLIENT_SECRET` | OAuth2 client secret for Immich provider |
| `CF_ACCESS_CLIENT_ID` | OAuth2 client ID for Cloudflare Access provider |
| `CF_ACCESS_CLIENT_SECRET` | OAuth2 client secret for Cloudflare Access provider |
| `CF_ACCESS_CALLBACK_URL` | `https://<team>.cloudflareaccess.com/cdn-cgi/access/callback` |

---

## App SSO Status

### Native OIDC (Authentik as issuer)

These apps initiate their own OIDC login flow pointing at Authentik.

| App | Issuer URL | Notes |
|-----|-----------|-------|
| Immich | `https://auth.sulibot.com/application/o/immich/` | Configured via `valuesFrom: immich-oidc` Secret in HelmRelease |
| Paperless-ngx | `https://auth.sulibot.com/application/o/paperless/` | To be configured |
| Karakeep | `https://auth.sulibot.com/application/o/karakeep/` | To be configured |
| Home Assistant | `https://auth.sulibot.com/application/o/home-assistant/` | To be configured |
| Actual Budget | `https://auth.sulibot.com/application/o/actual/` | To be configured |

### Header auth (trusted proxy header)

These apps do not support OIDC but accept a trusted header to identify the user.
Requires an Authentik Proxy Outpost deployed in front of the app.

| App | Header | Guard setting |
|-----|--------|--------------|
| Firefly III | `HTTP_X_AUTHENTIK_EMAIL` | `AUTHENTICATION_GUARD=remote_user_guard` (currently commented — requires outpost first) |
| Filebrowser | `X-Webauth-User` | `FILEBROWSER_NOAUTH=true` |

### CF Access header auth (external only, no Authentik needed)

Cloudflare injects `Cf-Access-Authenticated-User-Email` into every authenticated request.
Apps behind CF Access can optionally read this header to display the logged-in user,
without needing any OIDC integration.

### No SSO (own auth / API key)

| Apps |
|------|
| Plex, Tautulli, Seerr — Plex auth |
| Radarr, Sonarr, Prowlarr, Lidarr, Autobrr — API key |
| NZBGet, qBittorrent — basic auth |
| Filestash — basic auth (OIDC is enterprise-only in AGPL) |

---

## Immich OIDC — Implementation Detail

Immich's `clientId` and `clientSecret` cannot be stored in plaintext in git. They are
injected via Flux `valuesFrom`:

1. **ExternalSecret** `immich-oidc` reads from the `authentik` 1Password item and creates
   a Secret with key `values.yaml` containing the OAuth credentials.
2. **HelmRelease** references `valuesFrom: [{kind: Secret, name: immich-oidc}]`.
3. The non-secret OAuth config (issuer URL, scopes, button text) is in the HelmRelease
   `values` inline.

Relevant files:
- [`kubernetes/apps/tier-2-applications/immich/app/externalsecret.yaml`](../kubernetes/apps/tier-2-applications/immich/app/externalsecret.yaml)
- [`kubernetes/apps/tier-2-applications/immich/app/helmrelease.yaml`](../kubernetes/apps/tier-2-applications/immich/app/helmrelease.yaml)

---

## Pending / To Do

- [x] Add `IMMICH_OIDC_CLIENT_ID`, `IMMICH_OIDC_CLIENT_SECRET`, `CF_ACCESS_CLIENT_ID`,
      `CF_ACCESS_CLIENT_SECRET`, `CF_ACCESS_CALLBACK_URL` fields to the `authentik`
      1Password item (Kubernetes vault)
- [x] Configure Cloudflare Access applications (immich, firefly, filebrowser, filestash, auth) — policy: allow sulibot@gmail.com via Google
- [x] Configure Google as identity provider in Cloudflare Zero Trust
- [ ] Configure Authentik OIDC for Paperless-ngx, Karakeep, Home Assistant, Actual Budget
      (blueprints + app helmrelease updates)
- [ ] Deploy Authentik Proxy Outpost for Firefly III and Filebrowser (enables header auth)
- [x] Switch `cert-manager.io/cluster-issuer` to `letsencrypt-production` on both gateways
- [x] Remove `noTLSVerify: true` from cloudflare-tunnel config
