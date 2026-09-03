# Supabase API gateway behind Cilium

Traffic: clients -> Cilium gateway-internal (TLS) -> Supabase Envoy :8000
-> the existing Supabase services. PostgreSQL and PVCs are not migrated.

The community supabase Helm chart 0.7.2 still ships Kong. This Kustomization
deploys the gateway from official Supabase Docker Compose independently of that
chart, while retaining the chart for the remaining services.

## Upstream provenance

- Repository: https://github.com/supabase/supabase
- Commit: `bdfd69e9554a1f9fb76d0aee3b57d5eec5ac3dbe`
- Source: `docker/volumes/api/envoy/`
- Image: `envoyproxy/envoy:v1.39.0`, pinned by multi-platform digest.
- The four files in `upstream/` are unmodified copies, including the listener's
  Lua filters, RBAC, CORS, dashboard basic auth, and blocked management routes.
- License: upstream Apache-2.0 (https://github.com/supabase/supabase/blob/bdfd69e9554a1f9fb76d0aee3b57d5eec5ac3dbe/LICENSE).

At startup Docker DNS names, the Realtime tenant Host header, and the listener socket are adapted: cluster
names resolve to existing Kubernetes Services, and the listener accepts both
IPv6 and IPv4. Cilium reaches an IPv6 Service; existing internal upstream
Services stay IPv4. Envoy runs two workers and exposes no admin Service (the
admin listener remains loopback-only). API keys are rendered into memory-backed
storage from the existing Kubernetes Secret. Generated ConfigMaps disable Flux
variable substitution so upstream placeholders reach the container unchanged.

Legacy HS256 API keys remain in use, as supported by upstream. Introducing
opaque/asymmetric keys is a separate Auth/JWT migration, not part of replacing
Kong. This gateway update does not claim that chart 0.7.2's other images match
the latest Docker Compose release.

Functions explicitly enables `VERIFY_JWT=true` (the chart defaults to false).
No application Edge Functions are installed yet; the validation checks the
runtime's authentication boundary, not a deployed business function.

## Upgrade and rollback

Update all four upstream files from one pinned commit, review their diff,
update the matching image and digest, render Kustomize, validate with Envoy,
then run `python3 scripts/validate-supabase-gateway.py` before and after routing
traffic. The generated ConfigMap hash causes config updates to roll the pod.
Secret reloader restarts the deployment on API key or dashboard secret changes.

For rollback, first re-enable Kong and its IPv6 listener/Service patches from
Git history. Wait for it to become Ready, then point the HTTPRoute and Studio /
Functions SUPABASE_URL back to Kong. Do not delete database PVCs or change keys.
