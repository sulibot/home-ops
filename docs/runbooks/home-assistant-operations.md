# Home Assistant Runbook

## Purpose

This runbook documents the Home Assistant deployment in the home-ops cluster from three perspectives:

- Config: where settings actually live and which parts are GitOps-managed versus stateful.
- Infrastructure: how Home Assistant is exposed, authenticated, backed up, and integrated with related services.
- Operations: how to change it safely, validate health, troubleshoot breakage, and recover from mistakes.

This is the operational source of truth for the current Kubernetes deployment, not a generic Home Assistant guide.

## Scope

This runbook covers:

- Home Assistant in namespace `default`
- Helm/Flux deployment and routing
- Authentication model and security posture
- Persistent storage and backup behavior
- HACS bootstrap model
- Matter and Thread integration dependencies
- Google Home manual cloud-to-cloud endpoint
- Runtime UID/GID and filesystem ownership expectations

## Source of Truth

### Git-managed

Primary declarative configuration:

- `/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-2-applications/home-assistant/app/helmrelease.yaml`
- `/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-2-applications/home-assistant/app/externalsecret.yaml`
- `/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-2-applications/home-assistant/ks.yaml`
- `/Users/sulibot/repos/github/home-ops/terraform/infra/live/services/cloudflare-access/terragrunt.hcl`

These files define:

- the Home Assistant image and pod security settings
- service exposure and HTTPRoutes
- persistent volume claims and VolSync integration
- Cloudflare DNS and public access policy for the Google endpoint

### Stateful runtime config

These are not currently GitOps-managed and live on the Home Assistant config PVC:

- `/config/configuration.yaml`
- `/config/secrets.yaml`
- `/config/SERVICE_ACCOUNT.json`
- `/config/.storage/*`
- `/config/custom_components/*`
- `/config/home-assistant_v2.db`

This matters operationally:

- Git can restore the Kubernetes deployment, but not the live Home Assistant configuration state.
- A bad manual edit to `/config/configuration.yaml` can break startup independently of Flux.
- UI integrations, entity registry, auth state, and many mobile/app settings live under `/config/.storage`.

## Current Architecture

### Deployment

- Namespace: `default`
- Workload type: `Deployment`
- Release name: `home-assistant`
- Controller strategy: `Recreate`
- Image: `ghcr.io/home-operations/home-assistant:2026.3.1@sha256:067e54...`

`Recreate` means restart behavior is sensitive to stuck old pods. If the old pod is stranded on a dead node, the replacement will not come up until the old one is removed.

### Networking

Home Assistant has:

- default cluster networking on Cilium
- a single Multus attachment on VLAN 31:
  - `fd00:31::251`
  - `10.31.0.251`

Practical access paths:

- Canonical internal HA URL: `http://[fd00:31::251]:8123`
- IPv4 fallback HA URL: `http://10.31.0.251:8123`
- VLAN 30 reaches Home Assistant by routed access into VLAN 31

### HTTP routes

Home Assistant is internal-only in the intended design.

- No public Home Assistant route is part of the target topology.
- The canonical endpoint is the VLAN 31 IPv6 address.
- IPv4 remains valid as a compatibility path only.

## Authentication Model

### Human access

Human browser and app access use the direct internal Home Assistant endpoint:

- preferred: `http://[fd00:31::251]:8123`
- fallback: `http://10.31.0.251:8123`

Home Assistant local auth is the intended path in this topology.

### Local access

Home Assistant also uses `trusted_networks`:

- `fd00:31::/64`
- `10.31.0.0/24`

and currently:

- `allow_bypass_login: true`

This is convenient, but it is a trust shortcut. Anyone on those subnets can bypass the normal login screen.

### Google access

No Google cloud-to-cloud endpoint is part of the current intended topology.

## Security Posture

### Current pod hardening

Home Assistant now runs with:

- `automountServiceAccountToken: false`
- dedicated service account: `home-assistant`
- `allowPrivilegeEscalation: false`
- `capabilities.drop: ["ALL"]`
- `readOnlyRootFilesystem: true` on the app container
- `privileged: false`
- `seccompProfile: RuntimeDefault`
- non-root runtime user

### Current HA-side hardening

`/config/configuration.yaml` contains:

- `ip_ban_enabled: false`
- `login_attempts_threshold: 5`
- explicit `trusted_proxies`

### What is still intentionally permissive

- `trusted_networks` bypass remains enabled
- Home Assistant local auth and trusted networks remain the primary local access model

### Security recommendations

Keep doing:

- `google_assistant.expose_by_default: false`
- expose only specific entities
- keep HA and custom integrations updated
- prefer the local endpoint for administration when possible

Avoid:

- widening `trusted_networks` further

## Persistent Storage

### PVCs

Home Assistant uses:

- `home-assistant-config`
  - mounted at `/config`
- `home-assistant-config-cache`
  - mounted at `/config/.venv`

Storage class:

- `csi-cephfs-config-sc`

### Ownership model

Current expected owner/group:

- UID: `1000`
- GID: `1000`

This was migrated from mixed `568` / `1000:568` ownership to a clean `1000:1000` model.

### Completed UID migration

Completed on `2026-03-10`.

Migration summary:

- previous pod runtime UID/GID: `568:568`
- previous PVC ownership: mixed `568:568`, `1000:568`, and root-owned directories
- target runtime UID/GID: `1000:1000`
- result: verified clean runtime and volume ownership alignment at `1000:1000`

Procedure used:

1. scaled `home-assistant` deployment to `0`
2. mounted both PVCs in a one-shot maintenance pod
3. recursively `chown`ed:
   - `/config` -> `1000:1000`
   - `/config-cache` -> `1000:1000`
4. updated the HelmRelease pod security context to `runAsUser: 1000`, `runAsGroup: 1000`, `fsGroup: 1000`
5. reconciled Flux and verified the new pod started successfully

Post-migration verification:

- runtime user in container: `uid=1000 gid=1000 groups=1000`
- key paths owned by `1000:1000`:
  - `/config`
  - `/config/.storage`
  - `/config/.venv`
  - `/config/custom_components`
  - `/config/home-assistant_v2.db`
  - `/config/SERVICE_ACCOUNT.json`
- SQLite database opened successfully after migration
- Google Assistant endpoint remained healthy after migration

Operational rule:

- do not manually reintroduce mixed ownership on `/config` or `/config/.venv`
- if another container needs access, prefer group-compatible access or a copy of the data rather than ad hoc chmod changes

### Backup model

VolSync backs up the config PVC.

Relevant resource:

- `ReplicationSource/home-assistant-src`

Important details:

- source PVC: `home-assistant-config`
- mover security context already runs as `1000:1000`
- restore behavior depends on PVC content, not just Git

Operational implication:

- if runtime config is damaged, backup/restore is a valid recovery path
- for identity/ownership-sensitive migrations, verify VolSync mover UID/GID alignment before changing HA runtime UID

## HACS Model

HACS is installed via a pinned init container, not manually.

Current behavior:

- init container downloads HACS `2.0.5`
- installs to `/config/custom_components/hacs`
- if that exact version is already present, it exits without changes

Why this model exists:

- deterministic bootstrap
- no custom HA image required
- works with persistent `/config`

What is not GitOps-managed:

- HACS-installed repositories after bootstrap
- custom integrations downloaded by HACS into `/config/custom_components`

Operational implication:

- HACS bootstrap is reproducible
- HACS-managed integrations are still stateful runtime content

## Matter and Thread

### Matter

Home Assistant Matter integration is configured to use the internal cluster service URL:

- `ws://matter-server.matter-server.svc.cluster.local:5580/ws`

This is the correct HA-to-Matter path in this cluster.

Do not replace it with:

- `matter-server.sulibot.com`
- `10.31.0.252`

unless behavior changes are intentionally validated.

### Thread / OTBR

OTBR runs outside Kubernetes in a Proxmox LXC.

Current endpoint:

- `http://otbr01.sulibot.com:8081`

HA uses:

- `OpenThread Border Router` integration
- `Thread` integration

The current Thread network is expected to be present and preferred before Matter-over-Thread commissioning works well.

Operational split:

- HA and Matter Server are in Kubernetes
- OTBR is not
- Thread radio access remains outside Kubernetes, but Matter-over-Thread still depends on the pod network being able to route to the Thread OMR prefix.
- The current static Thread OMR route workaround remains required until the Kubernetes networking model handles that path explicitly.

## Normal Operations

### Check health

```bash
kubectl -n default get deploy,pod,svc,httproute | rg home-assistant
flux get kustomization home-assistant -n flux-system
kubectl -n default logs deploy/home-assistant --tail=200
```

### Restart HA

```bash
kubectl -n default rollout restart deploy/home-assistant
kubectl -n default rollout status deploy/home-assistant --timeout=180s
```

Because the deployment uses `Recreate`, if restart hangs, check for a stuck old pod on a dead node.

### Validate internal endpoints

```bash
curl -I 'http://[fd00:31::251]:8123'
curl -I http://10.31.0.251:8123
```

Expected:

- both endpoints return the Home Assistant HTTP listener
- IPv6 is the preferred internal path

### Validate local runtime config

```bash
kubectl -n default exec deploy/home-assistant -- sh -lc 'sed -n "1,260p" /config/configuration.yaml'
kubectl -n default exec deploy/home-assistant -- sh -lc 'ls -l /config/SERVICE_ACCOUNT.json'
```

## Troubleshooting

### Symptom: restart hangs forever

Likely cause:

- old pod stuck on a `NotReady` node
- `Recreate` strategy prevents replacement pod from starting

Actions:

1. identify old pod/node
2. cordon the bad node if needed
3. force-delete the stuck pod
4. wait for replacement to schedule elsewhere

### Symptom: Google link page shows `Login aborted`

Likely cause:

- aborted HA OAuth flow in embedded browser session
- auth provider mix with stale session state

Actions:

1. start the link flow again
2. choose `Home Assistant Local`
3. log in with the HA local account
4. avoid using the Authentik route for Google linking

### Symptom: `/api/google_assistant` returns `404`

Likely cause:

- `google_assistant:` block missing or invalid in `/config/configuration.yaml`
- missing `/config/SERVICE_ACCOUNT.json`
- HA not restarted after config change

Actions:

1. verify config block
2. verify service account file exists
3. restart HA
4. re-check endpoint

### Symptom: HA starts but custom integrations fail

Likely cause:

- HACS/custom component state incompatible with current HA version
- venv rebuild issue

Actions:

1. inspect logs for failing integration names
2. disable or update offending custom integration
3. do not assume the core deployment is broken if only HACS content is bad

### Symptom: file permission errors after runtime/user changes

Likely cause:

- mixed PVC ownership
- runtime UID/GID does not match volume content

Actions:

1. stop HA
2. mount PVCs in a one-shot maintenance pod
3. recursively `chown` to the intended UID/GID
4. bring HA back with the same UID/GID in the pod security context

Do not use broad `chmod 777` style fixes. They mask the actual state and create more drift.

## Recovery and Rollback

### If the runtime UID migration fails

Safe rollback path:

1. scale HA down
2. restore previous ownership on PVCs if necessary
3. revert the HelmRelease UID/GID change in Git
4. reconcile Flux
5. if runtime state is corrupted, restore from VolSync backup

### If Google integration must be disabled quickly

Two independent levers exist:

1. Cloudflare side
   - remove `ha-google.sulibot.com` DNS and bypass app in Terraform
2. HA side
   - remove or comment `google_assistant:` from `/config/configuration.yaml`

Use Cloudflare removal first if the goal is immediate public exposure shutdown.

## Change Management Guidance

### GitOps-safe changes

Safe to do declaratively in Git:

- pod security settings
- routes and hostnames
- service account usage
- Cloudflare DNS / Access policy for the Google endpoint
- image version changes

### Stateful changes requiring runtime handling

Treat these as runtime changes, not pure GitOps:

- `/config/configuration.yaml`
- `/config/SERVICE_ACCOUNT.json`
- entity exposure tuning for Google
- auth provider adjustments in Home Assistant runtime
- most HACS content

If you want full GitOps for HA configuration later, design that as a separate project. Current state is intentionally hybrid.

## Recommended Future Improvements

1. Move HA runtime config into a managed declarative source where practical
2. Reduce `trusted_networks` blast radius if possible
3. Explicitly document the Google-exposed entities once chosen
4. Add a small maintenance job or documented procedure for PVC ownership migrations
5. Decide whether `/config` state should remain manual-first or be partially GitOps-managed

## Quick Reference

### Key files

- HelmRelease: `/Users/sulibot/repos/github/home-ops/kubernetes/apps/tier-2-applications/home-assistant/app/helmrelease.yaml`
- HA runtime config: `/config/configuration.yaml`

### Key URLs

- Local HA preferred: `http://[fd00:31::251]:8123`
- Local HA fallback: `http://10.31.0.251:8123`
- OTBR: `http://otbr01.sulibot.com:8081`

### Key commands

```bash
flux get kustomization home-assistant -n flux-system
kubectl -n default get deploy,pod,svc,httproute | rg home-assistant
kubectl -n default logs deploy/home-assistant --tail=200
kubectl -n default rollout restart deploy/home-assistant
```
