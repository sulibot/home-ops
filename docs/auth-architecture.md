# Authentication Architecture

## Design Principles

### External Access (internet via Cloudflare Tunnel)

| App type | Authentication model | Notes |
|----------|----------------------|-------|
| **Apps behind CF Access** | Cloudflare Access with Authentik as OIDC IdP | Cloudflare Access is the edge gate. Authentik is used as the IdP for Cloudflare Access, and apps may still use Authentik (OIDC/proxy) and/or native app auth. |
| **Passthrough apps** (Plex, Seerr/Jellyseerr) | App-owned authentication | Cloudflare Access `Bypass` policy is applied intentionally. |

### Internal Access (LAN via gateway)

| App type | Preferred authentication | Notes |
|----------|--------------------------|-------|
| **Authentik-integrated apps** | Native OIDC -> proxy outpost/header auth | Prefer native OIDC when the app supports it; use the Authentik proxy outpost when OIDC is unavailable or impractical. |
| **Apps with multiple auth modes** | Google via Authentik · Authentik-native account · native app accounts | Keep all relevant options available when useful for collaboration, app-specific roles, service/API access, or break-glass access. |
| **Passthrough / minimal apps** | None (LAN trust boundary) | LAN trust is the outer boundary for selected internal-only services. |

**Key principle**: Cloudflare Access is the external enforcement layer. It gates internet traffic before requests reach the cluster. Authentik provides centralized identity for both edge and in-cluster integrations (Google OAuth and Authentik-native credentials). Native app accounts may coexist when operationally useful.

---

## Overview

Authentication is applied in **two independent layers**, depending on the access path:

| Path | Enforcement gate | Identity provider |
|------|------------------|-------------------|
| External (internet) | Cloudflare Access | Authentik OIDC (with Google source and/or Authentik-native login, depending on Authentik flow) |
| Internal (LAN) | Authentik (proxy outpost or native OIDC), or app-local auth | Google OAuth via Authentik, Authentik-native credentials, and/or app-native auth (depending on app) |

No firewall ports are opened. All external traffic enters through a **Cloudflare Tunnel** (a persistent outbound connection from `cloudflared` running in-cluster).

---

## Network Gateways

Two Cilium Gateway API gateways are deployed in the `network` namespace:

| Gateway | IP | Purpose |
|---------|----|---------|
| `gateway-tunnel` | `10.101.250.11` | Externally reachable apps (via Cloudflare Tunnel) and LAN access to those same apps |
| `gateway-internal` | `10.101.250.12` | Internal-only apps (LAN only) |

Both IPs are BGP-advertised and covered by a valid Let's Encrypt wildcard certificate (`*.sulibot.com`). `cloudflared` connects to `gateway-tunnel` via the cluster service `cilium-gateway-gateway-tunnel.network.svc.cluster.local:443`.

### Apps on `gateway-tunnel` (external + LAN)

| Hostname | App | Auth pattern |
|----------|-----|--------------|
| `auth.sulibot.com` | Authentik | Direct Authentik login page (CF Access bypassed intentionally) |
| `filebrowser.sulibot.com` | FileBrowser Quantum | Native OIDC via Authentik (local/password login disabled) |
| `firefly.sulibot.com` | Firefly III | Authentik proxy outpost -> header auth |
| `filestash.sulibot.com` | Filestash | CF Access externally; app-local auth on Filestash |
| `hass.sulibot.com` | Home Assistant (browser) | Native OIDC via Authentik (`hass-oidc-auth`) |
| `hass-app.sulibot.com` | Home Assistant (app/discovery) | Native OIDC via Authentik (`hass-oidc-auth`), WARP required externally |
| `immich.sulibot.com` | Immich | Native OIDC via Authentik |
| `vikunja-app.sulibot.com` | Vikunja (app) | App-safe endpoint, WARP required externally |
| `plex.sulibot.com` | Plex | Plex account (no WARP requirement externally) |
| `seerr.sulibot.com` | Jellyseerr | Plex/own auth (no WARP requirement externally) |

### Apps on `gateway-internal` (LAN only)

LAN-only apps currently routed through `gateway-internal` (`10.101.250.12`):

| Hostname | App | Auth pattern |
|----------|-----|--------------|
| `actual.sulibot.com` | Actual Budget | Native OIDC via Authentik |
| `alertmanager.sulibot.com` | Alertmanager | Internal ops endpoint (auth/config varies) |
| `atuin.sulibot.com` | Atuin | Atuin token / app auth |
| `autobrr.sulibot.com` | Autobrr | App-local auth |
| `bookshelf.sulibot.com` | Bookshelf | App-local auth |
| `emby.sulibot.com` | Emby | Emby account |
| `echo.sulibot.com` | Echo (test app) | Minimal / no auth (LAN only) |
| `gatus.sulibot.com` | Gatus | Internal ops endpoint (auth/config varies) |
| `status.sulibot.com` | Gatus (alias) | Internal ops endpoint (auth/config varies) |
| `go2rtc.sulibot.com` | go2rtc | App-local auth / LAN trust |
| `grafana.sulibot.com` | Grafana | Grafana auth (LAN route) |
| `jaeger.sulibot.com` | Jaeger | Internal ops endpoint (auth/config varies) |
| `jellyseerr.sulibot.com` | Jellyseerr | Plex/own auth |
| `requests.sulibot.com` | Jellyseerr (alias) | Plex/own auth |
| `karakeep.sulibot.com` | Karakeep | Native OIDC via Authentik |
| `kiali.sulibot.com` | Kiali | Internal ops endpoint (auth/config varies) |
| `kopia.sulibot.com` | Kopia | App-local auth |
| `kromgo.sulibot.com` | Kromgo | Internal ops endpoint |
| `lazylibrarian.sulibot.com` | LazyLibrarian | App-local auth |
| `lidarr.sulibot.com` | Lidarr | API key / local auth |
| `nzbget.sulibot.com` | NZBGet | App-local auth |
| `overseerr.sulibot.com` | Overseerr | Plex/own auth |
| `paperless.sulibot.com` | Paperless-ngx | Native OIDC via Authentik |
| `prometheus.sulibot.com` | Prometheus | Internal ops endpoint (auth/config varies) |
| `prowlarr.sulibot.com` | Prowlarr | API key / local auth |
| `qbittorrent.sulibot.com` | qBittorrent | App-local auth |
| `qui.sulibot.com` | Qui | App-local auth / minimal |
| `radarr.sulibot.com` | Radarr | API key / local auth |
| `radarr-4k.sulibot.com` | Radarr (4K) | API key / local auth |
| `sabnzbd.sulibot.com` | SABnzbd | App-local auth |
| `slskd.sulibot.com` | slskd | App-local auth |
| `sonarr.sulibot.com` | Sonarr | API key / local auth |
| `sonarr-4k.sulibot.com` | Sonarr (4K) | API key / local auth |
| `tautulli.sulibot.com` | Tautulli | App-local auth |
| `thelounge.sulibot.com` | The Lounge | App-local auth |
| `victoria-logs.sulibot.com` | VictoriaLogs | Internal ops endpoint |
| `zigbee.sulibot.com` | Zigbee UI/service | LAN trust / local auth |
| `zwave.sulibot.com` | Z-Wave UI/service | LAN trust / local auth |

`home-assistant.sulibot.com` is intentionally on `gateway-tunnel`, not `gateway-internal`.

---

## Cloudflare Access (External)

### Architectural Decision: Cloudflare Access uses Authentik as OIDC IdP

**Rationale**: Cloudflare Access remains the edge enforcement point, while Authentik centralizes identity policy and upstream source selection (Google + Authentik-native accounts) for app and edge SSO.

```
Internet -> Cloudflare Edge (Access policy) -> Authentik OIDC (as CF IdP) -> Tunnel -> gateway-tunnel -> App
                                                                                              ↓ (for OIDC/outpost apps)
                                                                                   Authentik (OIDC/proxy/session)
```

### Recommended layered model (source of truth)

Cloudflare Access is the **internet gate**. Authentik and apps are the **application identity/session layer**.

External path (internet):

1. User opens `https://<app>.sulibot.com`.
2. Cloudflare Access policy evaluates first (wildcard allow + explicit bypass list).
3. If no valid CF session exists, Cloudflare redirects to Authentik (configured as CF's OIDC IdP).
4. Authentik completes login flow and returns OIDC code/token to Cloudflare.
5. Cloudflare issues Access session (`CF_Authorization`) and allows request forwarding.
6. Cloudflare Tunnel forwards to `gateway-tunnel` (`10.101.250.11`) in-cluster.
7. App applies its own auth integration:
   - Immich/FileBrowser: native OIDC via Authentik
   - Firefly: Authentik outpost proxy/header auth
   - Home Assistant: native OIDC via Authentik (`hass-oidc-auth`)

Internal path (LAN):

1. Split DNS resolves hostnames to local gateway IPs.
2. Traffic goes directly to Cilium gateway and does not traverse Cloudflare edge.
3. App/AuthentiK flow runs directly (OIDC, outpost header auth, or app-local auth depending on app).

Shared-session caveat:

- CF and each app are separate OIDC clients.
- They do not share tokens directly.
- They can share Authentik SSO state when the browser already has a valid Authentik session cookie.
- Second prompts can still occur if session/cookies expire, hostname/cookie scope differs, or flow policy explicitly requires re-auth.

### Why CF IdP is Authentik (not Google direct)

Using Authentik as CF IdP keeps one identity authority for:

- Google and Authentik-native users
- app OIDC providers and proxy outpost policies
- consistent account mapping and lifecycle behavior across apps

Using Google directly in CF can reduce managed surface area, but increases split-identity risk when apps still use Authentik internally (account mismatch, login-method conflicts, callback/redirect edge cases).

### Cloudflare Access configuration

In Zero Trust -> Access -> Applications:

| Application | Hostname(s) | Policy | Notes |
|-------------|-------------|--------|-------|
| `*.sulibot.com` | `*.sulibot.com` | Allow approved users | Wildcard browser/email gate for all non-bypass, non-app hosts |
| `auth (bypass)` | `auth.sulibot.com` | Bypass | Required so Authentik OIDC endpoints are reachable for Cloudflare Access and app callbacks |
| `auth + public bypass` | `auth.sulibot.com`, `atuin.sulibot.com`, `plex.sulibot.com`, `overseerr.sulibot.com`, `requests.sulibot.com` | Bypass | Publicly reachable through Tunnel; app handles auth |
| `WARP-only apps` | `immich-app.sulibot.com`, `hass-app.sulibot.com`, `vikunja-app.sulibot.com` | WARP only | Requires an enrolled WARP client |

**Important**: `auth.sulibot.com` remains intentionally bypassed in Cloudflare Access. Browser-style hosts fall under the wildcard email gate unless explicitly bypassed. App-specific hosts use dedicated WARP-only policies.

**Approved user emails** (Zero Trust -> Access -> Access Groups):
- `bcwallace@gmail.com`
- `bodawee@gmail.com`
- `sarah.kalas@gmail.com`
- `munirah.ahmad1@gmail.com`
- `sulaiman.ahmad@gmail.com`
- `sulibot@gmail.com`

### Cloudflare Tunnel configuration

Stored as a Kubernetes Secret (via ExternalSecret from 1Password):
`kubernetes/apps/tier-1-infrastructure/cloudflare-tunnel/app/externalsecret.yaml`

```yaml
ingress:
  - hostname: "*.sulibot.com"
    originRequest:
      http2Origin: true
      noTLSVerify: true        # CF connects over HTTPS to the gateway, but cannot validate the internal cert chain in this path
      originServerName: sulibot.com  # SNI must match the wildcard LE cert CN
    service: https://cilium-gateway-gateway-tunnel.network.svc.cluster.local:443
  - service: http_status:404
```

> `noTLSVerify: true` is required on the tunnel's internal origin connection path. `originServerName` ensures SNI matches the wildcard certificate so the gateway serves the correct certificate.

---

## Internal (LAN) Access

### LAN DNS requirements

LAN clients must resolve `*.sulibot.com` to the **local gateway IPs**, not Cloudflare anycast IPs. If DNS falls through to public resolvers, Cloudflare returns `CF Error 1003 (Direct IP access not allowed)`.

**Mikrotik DNS static entries (required overrides for `gateway-tunnel` apps):**

All `gateway-tunnel` apps must resolve to `10.101.250.11` on LAN:

```
auth.sulibot.com             -> 10.101.250.11
filebrowser.sulibot.com      -> 10.101.250.11
firefly.sulibot.com          -> 10.101.250.11
filestash.sulibot.com        -> 10.101.250.11
home-assistant.sulibot.com   -> 10.101.250.11
immich.sulibot.com           -> 10.101.250.11
plex.sulibot.com             -> 10.101.250.11
seerr.sulibot.com            -> 10.101.250.11
```

All `gateway-internal` apps use `10.101.250.12`. A wildcard entry (`*.sulibot.com -> 10.101.250.12`) covers the default case; the specific overrides above take precedence for `gateway-tunnel` apps.

ExternalDNS (Mikrotik webhook provider) automatically manages these records from `HTTPRoute` hostnames. Manually added records without TXT ownership are ignored by ExternalDNS; delete them so ExternalDNS can recreate and own them.

> On LAN, Cloudflare Access is bypassed entirely. Requests go directly to the Cilium gateway.
> Authentik-integrated apps may still redirect to Authentik for OIDC/SSO; app-native accounts remain available where configured.

---

## Authentik

Authentik is served at `https://auth.sulibot.com` and deployed from:
`kubernetes/apps/tier-2-applications/authentik/`

### Authentik blueprints (GitOps)

Blueprints are maintained in `blueprints/` (rendered into an inline ConfigMap) and instantiated on Authentik worker startup. They are idempotent and safe to re-apply.

| Blueprint file | Purpose |
|----------------|---------|
| `google-source.yaml` | Google OAuth source + silent enrollment flow |
| `proxy-providers.yaml` | Proxy providers + outpost registration for Firefly |
| `filebrowser-provider.yaml` | OIDC provider for FileBrowser Quantum |
| `immich-provider.yaml` | OIDC provider for Immich |
| `karakeep-provider.yaml` | OIDC provider for Karakeep |
| `paperless-provider.yaml` | OIDC provider for Paperless-ngx |
| `actual-provider.yaml` | OIDC provider for Actual Budget |
| `cloudflare-access.yaml` | Cloudflare Access OIDC provider (actively used; CF IdP is Authentik) |

### Silent enrollment flow (Google OAuth -> Authentik user)

On a user's first Google login, Authentik runs `source-enrollment-silent`:

1. `ExpressionPolicy` `source-enrollment-set-username` runs **before** `UserWriteStage`
- Derives `username` from the Google `email` field
- Required because Google returns `email` and `name`, but not `username`
- Authentik 2025.x+ import path: `from authentik.stages.prompt.stage import PLAN_CONTEXT_PROMPT`
2. `UserWriteStage` creates the Authentik user
3. `UserLoginStage` signs the user in

**Known gotcha**: `PLAN_CONTEXT_PROMPT` moved from `authentik.flows.planner` to `authentik.stages.prompt.stage` in Authentik 2025.x. If the import path is wrong, enrollment fails with `"Aborting write to empty username"`, and the user sees `"Request has been denied"`.

### Authentication flow behavior

Two flow patterns are intentionally separated:

1. `default-authentication-flow`
- Default identification stage is local/password-oriented (`user_fields: [username, email]`).
- Google source is not injected here; this avoids unintended dual-button behavior on generic/default routes.

2. `sulibot-internal-authentication-flow`
- Single-host flow object bound to `auth.sulibot.com`.
- CF Access OIDC requests (redirect URI includes `cloudflareaccess.com/cdn-cgi/access/callback`) use a CF-specific identification stage (email field + Google source button).
- Non-CF requests use identifier-first routing:
  - `@gmail.com` -> Google source stage
  - non-`@gmail.com` -> Authentik password stage
- This preserves one-entry UX for app flows while making the external CF IdP path Google-first.

Users are therefore offered one of these methods based on flow/policy context:

| Credential type | How to use | Typical use case |
|-----------------|------------|------------------|
| **Google ID** | Click **Login with Google** | Standard human access for approved Google accounts |
| **Authentik-native account** | Enter username/email + password | Admins, service users, non-Google users, break-glass |
| **Native app account** | Use the application's own login flow (when enabled) | App-specific collaboration, roles, service/API access, or emergency fallback |

For Authentik-integrated apps (OIDC or proxy outpost), **Google ID** and **Authentik-native credentials** produce the same SSO outcome: Authentik issues a session/token and the app receives the identity via OIDC claims or injected headers. Native app accounts remain app-specific and may coexist.

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
| `GOOGLE_CLIENT_ID` | Google OAuth2 client ID (Authentik Google source) |
| `GOOGLE_CLIENT_SECRET` | Google OAuth2 client secret |
| `FILEBROWSER_OIDC_CLIENT_ID` | e.g. `filebrowser` |
| `FILEBROWSER_OIDC_CLIENT_SECRET` | random |
| `IMMICH_OIDC_CLIENT_ID` | e.g. `immich` |
| `IMMICH_OIDC_CLIENT_SECRET` | random |
| `KARAKEEP_OIDC_CLIENT_ID` | e.g. `karakeep` |
| `KARAKEEP_OIDC_CLIENT_SECRET` | random |
| `PAPERLESS_OIDC_CLIENT_ID` | e.g. `paperless` |
| `PAPERLESS_OIDC_CLIENT_SECRET` | random |
| `ACTUAL_OIDC_CLIENT_ID` | e.g. `actual` |
| `ACTUAL_OIDC_CLIENT_SECRET` | random |
| `OUTPOST_TOKEN` | API token for the Authentik proxy outpost deployment (random 40+ chars) |
| `CF_ACCESS_CLIENT_ID` | Cloudflare Access OIDC client ID (used by Authentik `cloudflare-access` provider) |
| `CF_ACCESS_CLIENT_SECRET` | Cloudflare Access OIDC client secret (used by Authentik `cloudflare-access` provider) |
| `CF_ACCESS_CALLBACK_URL` | Cloudflare Access callback URL (`https://<team>.cloudflareaccess.com/cdn-cgi/access/callback`) |

Also required from item `cloudnative-pg-superuser`:
- `POSTGRES_SUPER_PASS` (used by the `postgres-init` init container to create the DB)

---

## App Authentication Patterns

### Pattern 1: Authentik Proxy Outpost (header injection)

**Apps**: Firefly III

The `HTTPRoute` sends all traffic to `authentik-outpost:9000` (not directly to the app). Users authenticate with Authentik, and the outpost forwards the request to the app with identity headers.

```
Browser -> firefly.sulibot.com
    -> gateway-tunnel
    -> authentik-outpost:9000
        [no session] -> redirect to auth.sulibot.com -> Google/Auth-native login -> Authentik session
                        -> callback to firefly.sulibot.com/outpost.goauthentik.io/callback
        [session valid] -> proxy to internal_host with injected headers
    -> App receives X-Authentik-Email, X-Authentik-Username, etc.
```

**Outpost deployment**: `kubernetes/apps/tier-2-applications/authentik-outpost/`

**Outpost HelmRelease environment variables**:
- `AUTHENTIK_HOST` -> internal API URL: `http://authentik-server.default.svc.cluster.local`
- `AUTHENTIK_HOST_BROWSER` -> browser redirect URL: `https://auth.sulibot.com`
- `AUTHENTIK_INSECURE` -> `false`
- `AUTHENTIK_TOKEN` -> from `authentik-outpost-secret` (ExternalSecret -> 1Password `OUTPOST_TOKEN`)

**Proxy providers** (defined in `proxy-providers.yaml`):

| App | `external_host` | `internal_host` |
|-----|------------------|-----------------|
| `firefly-proxy` | `https://firefly.sulibot.com` | `http://firefly-app.default.svc.cluster.local:8080` |

**Firefly III header auth**: reads `HTTP_X_AUTHENTIK_EMAIL` using `AUTHENTICATION_GUARD=remote_user_guard`.
Use Authentik email as the identity key (best match for Google identities) so Firefly can
auto-create users on first login and map subsequent logins consistently.

**Firefly operational guidance**:
- Keep `X-Authentik-Email` as the identity header (stable key for Google-backed identities)
- Keep layered external auth (`CF Access` + Authentik outpost); users typically still enter credentials once because browser sessions are reused
- Allow Firefly to auto-create users on first login via header auth
- Maintain a documented break-glass/admin recovery path (DB/local app admin recovery)

### Pattern 2: Native OIDC (app initiates OIDC against Authentik)

**Apps**: FileBrowser Quantum, Immich, Home Assistant (`hass-oidc-auth`), Paperless-ngx, Karakeep, Actual Budget

The application redirects the user to Authentik. Users authenticate through Authentik (Google or Authentik-native credentials), and the application receives identity claims via OIDC. The `HTTPRoute` points directly to the app (no outpost in the path).

```
Browser -> filebrowser.sulibot.com
    -> gateway-tunnel -> filebrowser:80
        [no session] -> app redirects to auth.sulibot.com/application/o/filebrowser/authorize/
                        -> Google/Auth-native login -> Authentik session -> callback to app
        [session valid] -> app serves content
```

| App | Authentik issuer URL | Blueprint | Account auto-create |
|-----|----------------------|-----------|---------------------|
| FileBrowser Quantum | `https://auth.sulibot.com/application/o/filebrowser/` | `filebrowser-provider.yaml` | `createUser: true` in config.yaml |
| Immich | `https://auth.sulibot.com/application/o/immich/` | `immich-provider.yaml` | Yes |
| Home Assistant | `https://auth.sulibot.com/application/o/home-assistant/` | `home-assistant-provider.yaml` | Auto-link supported (`automatic_user_linking`); create-on-first-login not supported by plugin |
| Paperless-ngx | `https://auth.sulibot.com/application/o/paperless/` | `paperless-provider.yaml` | Yes |
| Karakeep | `https://auth.sulibot.com/application/o/karakeep/` | `karakeep-provider.yaml` | Yes |
| Actual Budget | `https://auth.sulibot.com/application/o/actual/` | `actual-provider.yaml` | Yes |

Client IDs and secrets are injected via ExternalSecret from 1Password into `authentik-secret`, then passed into each app via the app's own ExternalSecret.

**UX note (single credential entry)**:
- For externally exposed OIDC apps behind Cloudflare Access (for example Immich or FileBrowser),
  users may pass through both Cloudflare Access and Authentik/Google redirects.
- The browser often reuses existing Google/Authentik sessions, so users typically enter
  credentials only once even though multiple auth checks occur.
- Prompt frequency depends on Cloudflare Access, Authentik, and Google session state/expiry.

### Pattern 3: CF Access bypass + app-owned auth (passthrough)

**Apps**: Plex, Seerr/Jellyseerr

These apps have Cloudflare Access `Bypass` policies and therefore reach the cluster without a Cloudflare Google login gate. Authentication is handled by the application:
- Plex -> Plex account
- Seerr/Jellyseerr -> Plex account or local user

Account lifecycle is app-owned (including auto-creation where supported).

> Atuin can use this same pattern when exposed externally, but is currently routed on `gateway-internal` in this repo.

### Pattern 4: App-local auth / API key (LAN only, `gateway-internal`)

**Apps**: Radarr, Sonarr, qBittorrent, NZBGet, and similar tools

These apps are available only on LAN through `gateway-internal` (`10.101.250.12`). They are not exposed externally and typically use API keys, basic auth, or app-local accounts. LAN trust remains the outer boundary.

### Pattern 5: Filestash (direct app auth; OIDC-capable)

Filestash is on `gateway-tunnel`, so external requests are gated first by Cloudflare Access (Google). Authentication inside Filestash is handled by Filestash plugins.

**Preferred approach**:
- Use Filestash OIDC/OpenID (`plg_authenticate_openid`) for interactive users where possible.
- Keep native app auth plugins available when they better fit collaboration or backend storage access requirements.

Access behavior:
- **External**: Cloudflare Access (Google) -> Filestash auth (OIDC/OpenID preferred; native plugin auth optional)
- **Internal**: Filestash auth directly (OIDC/OpenID preferred; local / `htpasswd` / passthrough as needed)

**UX note (single credential entry)**:
- Externally, Filestash uses layered auth (Cloudflare Access + Filestash OIDC/OpenID).
- This can still behave like a single sign-in from the user's perspective: the browser may show
  brief redirects through Cloudflare Access and Authentik/Google, but credentials are typically
  entered only once because existing sessions/cookies are reused.
- Prompt frequency depends on Cloudflare Access, Authentik, and Google session state/expiry.

Common Filestash auth plugins:
- OIDC / OpenID: `plg_authenticate_openid`
- Local users: `plg_authenticate_local`
- `htpasswd`: `plg_authenticate_htpasswd`
- Passthrough: `plg_authenticate_passthrough`

Use plugin selection to match the collaboration model, backend credential model, and break-glass requirements.

Config is GitOps-managed via ExternalSecret (1Password item `filestash`):
- `ADMIN_PASSWORD` -> bcrypt hash of admin password
- `SECRET_KEY` -> session encryption key

The rendered config is stored in `filestash-secret` and mounted read-only at `/app/data/state/config/config.json`. The storage backend (CephFS content PVC) is preconfigured in `config.json` as a `local` connection at `/srv/data`.

---

## Adding a New App: Checklist

### New app using the Authentik proxy outpost (header injection)

1. Add the proxy provider and application to `proxy-providers.yaml`
2. Add the provider to the outpost `providers:` list in the same blueprint
3. In the app `HelmRelease`, point `HTTPRoute.backendRefs` to `authentik-outpost:9000`
4. Configure the app to trust the injected identity header(s) (for example `AUTHENTICATION_GUARD=remote_user_guard`)
5. If LAN access is required via `gateway-tunnel`, allow ExternalDNS to manage the Mikrotik DNS record

### New app using native OIDC

1. Add the OIDC provider and application to a blueprint file in `blueprints/`
2. Add the blueprint filename to `blueprintconfigmap.yaml`
3. Add `CLIENT_ID` and `CLIENT_SECRET` fields to the `authentik` 1Password item
4. Add an app ExternalSecret that reads those fields
5. Configure the app OIDC issuer URL as `https://auth.sulibot.com/application/o/<slug>/`
6. Enable account auto-creation (`createUser: true` or equivalent), if desired
7. If externally reachable, ensure the Cloudflare Access wildcard policy applies (or explicitly define a bypass policy)

---

## Troubleshooting

### CF Error 1003: "Direct IP access not allowed"

**Cause**: A LAN client resolves a `gateway-tunnel` hostname to Cloudflare public IPs instead of the local gateway IP `10.101.250.11`.

**Fix**: ExternalDNS should manage these records automatically. If a record was added manually without TXT ownership, delete it so ExternalDNS can recreate and claim it.

### Authentik shows "Request has been denied" on first Google login

**Cause 1**: Incorrect import path in the enrollment flow `ExpressionPolicy`
- Authentik 2025.x+ requires:
  `from authentik.stages.prompt.stage import PLAN_CONTEXT_PROMPT`
- Older path (`from authentik.flows.planner import PLAN_CONTEXT_PROMPT`) fails in 2025.x+

**Fix**: Check the `source-enrollment-set-username` policy expression:
`Flows -> Policies -> source-enrollment-set-username -> Expression`

**Cause 2**: `enrollment_flow` on the Google OAuth source is `None`
- This can happen if blueprint ordering creates the source before the flow exists.

**Fix** (Authentik Django shell):
```python
from authentik.sources.oauth.models import OAuthSource
from authentik.flows.models import Flow
source = OAuthSource.objects.get(slug='google')
source.enrollment_flow = Flow.objects.get(slug='source-enrollment-silent')
source.save()
```

### Authentik outpost redirects to `http://authentik-server.default.svc.cluster.local`

**Cause**: `AUTHENTIK_HOST_BROWSER` is not set on the outpost deployment.

**Fix**: Set `AUTHENTIK_HOST_BROWSER: "https://auth.sulibot.com"` in the outpost HelmRelease environment variables.

### FileBrowser Quantum shows the local login form instead of redirecting to OIDC

**Cause 1**: `createUser: false` (default)
- The user does not exist yet and OIDC auto-creation is disabled.

**Fix**: Set `oidc.createUser: true` in `config.yaml`.

**Cause 2**: Database is not persisted
- `FILEBROWSER_DATABASE` is ignored by FileBrowser Quantum.

**Fix**: Set `server.database: /config/database.db` in `config.yaml`.

**Cause 3**: OIDC client secret not synced from 1Password yet

**Fix**: Check sync status:
`kubectl get externalsecret filebrowser-oidc -n default`

### Authentik outpost returns `502 Bad Gateway`

**Cause**: `internal_host` in the proxy provider points to the wrong port.

**Fix**: Match `internal_host` to the Kubernetes Service port (not the container port).

---

## File Reference

| File | Purpose |
|------|---------|
| `kubernetes/apps/tier-1-infrastructure/cloudflare-tunnel/app/externalsecret.yaml` | Cloudflare Tunnel config (ingress rules, TLS settings) |
| `kubernetes/apps/tier-2-applications/authentik/app/helmrelease.yaml` | Authentik HelmRelease |
| `kubernetes/apps/tier-2-applications/authentik/app/blueprintconfigmap.yaml` | Authentik blueprint ConfigMap |
| `kubernetes/apps/tier-2-applications/authentik/app/blueprints/` | Authentik blueprint YAML files |
| `kubernetes/apps/tier-2-applications/authentik-outpost/app/helmrelease.yaml` | Authentik proxy outpost deployment |
| `kubernetes/apps/tier-2-applications/filebrowser/app/externalsecret-oidc.yaml` | FileBrowser OIDC config (templated `config.yaml` from 1Password) |
| `kubernetes/apps/tier-2-applications/filestash/app/externalsecret.yaml` | Filestash `config.json` (admin password, secret key, connections from 1Password) |
