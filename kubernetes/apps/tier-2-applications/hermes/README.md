# Hermes (staged)

This package is **not deployed**: the tier-2 tree includes `ks.yaml`, but its
Flux reconciliation is deliberately suspended. It adapts the [reference deployment][reference] to this
cluster's app-template chart, CephFS config PVC, 1Password Connect, and
`gateway-internal`. The base release starts only the authenticated dashboard;
the messaging gateway is disabled until a model, bot tokens, and explicit
sender allowlists have been configured.

The dashboard is a high-privilege shell and credentials management surface.
The basic-auth provider is suitable only for the cluster's trusted internal
gateway/VPN, **not** an internet-facing route. No code-server, host mount,
Kubernetes service-account token, inbound gateway Service, or Hermes API
server is configured. The image's root bootstrap sets up `/opt/data` and drops
the Hermes process to UID 10000; forcing `runAsNonRoot` would break that
upstream startup path. The shared CephFS claim contains Hermes config, API
keys entered through the dashboard, sessions, and workspace; back it up and
restrict access accordingly.

## Required before activation

Create a 1Password item named `hermes-dashboard` with these fields:

| Field | Value |
| --- | --- |
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` | Chosen admin username |
| `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH` | Hermes `scrypt` hash of a strong password |
| `HERMES_DASHBOARD_BASIC_AUTH_SECRET` | Stable random signing key, at least 32 bytes |

The [upstream instructions][dashboard-auth] show the hash function:
`from plugins.dashboard_auth.basic import hash_password`. Generate the hash
locally in the pinned Hermes image using an interactive password prompt (do
not put the plaintext password in a shell command/history):

```sh
docker run --rm -it --platform linux/amd64 --entrypoint python \
  docker.io/nousresearch/hermes-agent:v2026.9.24@sha256:fca358f12efd65bfaaca05884166f15c0e2788375ca30d77061ac1ebc96452b7 \
  -c 'from getpass import getpass; from plugins.dashboard_auth.basic import hash_password; print(hash_password(getpass()))'
openssl rand -base64 32
```

Save the outputs only in 1Password. An absent or invalid auth secret makes the
non-loopback dashboard fail closed. Before enabling the route for users, verify
`GET /api/status` reports `auth_required: true` and `auth_providers` includes
`basic`, then verify a protected page redirects to login when unauthenticated.
The status endpoint itself is intentionally public per upstream.

The dashboard can edit `config.yaml` and API keys on the shared PVC. Choose a
model/provider and add its own credential there; this package does not assume
an Anthropic account, reuse another app's key, or start an unconfigured bot.
For Telegram/Discord, configure bot tokens **and** comma-separated allowed
user IDs before changing `controllers.gateway.enabled` to `true`. Hermes
defaults to deny when no user is authorized. The gateway uses outbound
messaging connections and must remain a normal, always-running pod: an HTTP
idle timer would miss incoming messages.

The dashboard's own System page also exposes gateway Start/Stop controls.
Upstream's container supervisor knows to avoid auto-starting a gateway in a
dashboard-role container, but an authenticated administrator can still invoke
those controls. Do not use them in this split-pod deployment; manage the
separate Kubernetes gateway controller instead. Before any dashboard CRIU
test, verify no messaging gateway process is running in the dashboard pod.

## Activation and verification

1. Create and verify the dedicated 1Password item above without displaying
   its credential values in logs.
2. Change `spec.suspend` in `ks.yaml` to `false` in a reviewed change and
   publish the configuration to Flux's Git source. The staged local files
   alone do not change the live cluster. Confirm the resulting ExternalSecret
   becomes Ready before proceeding; the dashboard cannot start without it.
3. Verify the dashboard pod starts, its `/api/status` auth gate is on, login
   works via `https://hermes.sulibot.com`, and model configuration/API keys can
   be saved across a pod restart. Verify the internal gateway is not publicly
   routed and that the dashboard's IPv4-only Service is reachable from the
   internal Gateway. Its startup probe calls IPv4 loopback from inside the
   container, since an IPv6-first kubelet Pod-IP probe would not reach the
   image's documented `0.0.0.0` listener.
4. Only after model, bot tokens, allowlists, and outbound connectivity are
   tested, set `controllers.gateway.enabled: true`. Check both platforms from
   an authorized sender; no inbound gateway Service is needed.

The base is **not** a proven CRIU workload. The unreferenced
`overlays/zeropod` opts in only the dashboard pod on `solwk03`, with
`app=9119` TCP wake and a 30-minute idle delay. Do not point Flux at that
overlay until the Talos Zeropod runtime works end-to-end and a disposable
Hermes dashboard has passed repeated checkpoint/restore tests, including
login, WebSocket chat, filesystem state, and the shared-PVC behavior. The
gateway is never in the runtime overlay. Its memory and Kubernetes requests
remain resident; hibernation is not replica scale-to-zero.

Validation used `kubectl kustomize` for both variants and rendered the pinned
app-template 4.6.2 chart. This checks chart wiring, not Hermes startup, auth,
provider configuration, or CRIU compatibility on live Talos.

[reference]: https://github.com/joryirving/home-ops/blob/main/kubernetes/apps/base/llm/hermes/helmrelease.yaml
[dashboard-auth]: https://github.com/NousResearch/hermes-agent/blob/v2026.9.24/website/docs/user-guide/features/web-dashboard.md#usernamepassword-provider-no-oauth-idp
