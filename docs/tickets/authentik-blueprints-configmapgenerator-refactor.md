# Ticket: Deduplicate Authentik blueprints via configMapGenerator

- Status: Done
- Priority: Low
- Area: Kubernetes (authentik), Kustomize
- Created: 2026-07-28

## Summary

`kubernetes/apps/tier-2-applications/authentik/app/blueprints/*.yaml`
(`google-source.yaml`, `grafana-provider.yaml`, `vikunja-provider.yaml`,
etc.) look like the live Authentik blueprint config but are dead — not
referenced by `kustomization.yaml` (no `configMapGenerator`, not listed as
a resource) and not in `helmrelease.yaml`'s `blueprints.configMaps` (only
`authentik-blueprints`, sourced solely from `blueprintconfigmap.yaml`).

The actual deployed blueprints are ~18 separate `data` keys hand-pasted
inline into `blueprintconfigmap.yaml`, using the same filenames as the
standalone files but with content that has already drifted in places —
e.g. the real `google-source.yaml` key defines a silent-enrollment flow +
username-set policy the standalone file lacks, and the real
`default-authentication-identification` stage is deliberately
sources-free, unlike what the standalone file implies. See
[[project_authentik_dead_blueprints_dir]] (memory) — discovered while
wiring a Kanidm OIDC source (ENG-327) when an edit to the standalone file
had no effect and had to be redone in `blueprintconfigmap.yaml`.

This is a live trap: whoever edits Authentik blueprints next (human or
agent) has a 50/50 shot of editing the file that doesn't do anything.

## Design

Replace the hand-maintained `blueprintconfigmap.yaml` with a Kustomize
`configMapGenerator` that builds the same ConfigMap from the standalone
`blueprints/*.yaml` files:

```yaml
# kustomization.yaml
configMapGenerator:
  - name: authentik-blueprints
    files:
      - host-auth-flows.yaml=blueprints/host-auth-flows.yaml
      - google-source.yaml=blueprints/google-source.yaml
      - kanidm-source.yaml=blueprints/kanidm-source.yaml
      # ... one line per blueprint file, ~18 total
generatorOptions:
  disableNameSuffixHash: true  # helmrelease.yaml references the name literally
```

Work:
1. For each of the ~18 keys, diff the `blueprintconfigmap.yaml` version
   against the standalone `blueprints/` version and figure out which is
   correct (they've drifted - assume the inline/deployed version is
   authoritative unless a diff proves otherwise).
2. Write the resolved content into `blueprints/<name>.yaml`, delete the
   corresponding key from `blueprintconfigmap.yaml`.
3. Add the `configMapGenerator` block, delete `blueprintconfigmap.yaml`
   once empty.
4. `kubectl kustomize kubernetes/apps/tier-2-applications/authentik/app`
   must produce a byte-identical (or intentionally-corrected)
   `authentik-blueprints` ConfigMap to what's live today.

## Acceptance criteria

- [x] `blueprintconfigmap.yaml` deleted; `blueprints/*.yaml` are the only
      copies and are what Kustomize actually deploys.
- [x] `kubectl kustomize .../authentik/app` builds clean, ConfigMap name
      stays `authentik-blueprints` (no hash suffix).
- [x] Every content divergence found in step 1 is either resolved with a
      clear reason or flagged to the user rather than silently picked.

## Resolution (2026-07-28)

Extracted all 19 `data` keys from the live `blueprintconfigmap.yaml`
programmatically (PyYAML, not manual copy-paste, to avoid introducing new
drift). Diffed against the 7 pre-existing `blueprints/*.yaml` files:
`freshrss-provider.yaml` and `grafana-provider.yaml` were already
identical; `cloudbeaver-provider.yaml`, `cloudflare-access.yaml`,
`google-source.yaml`, `immich-provider.yaml`, and `vikunja-provider.yaml`
had drifted (the deployed version was newer in every case — missing
policy bindings, updated `issuer_mode`, missing silent-enrollment flow on
`google-source.yaml`). Deployed version kept in all cases. The other 12
keys had no standalone file at all and were created fresh from the
extracted content.

`kustomization.yaml` now has a `configMapGenerator` (`disableNameSuffixHash:
true` to keep the name `authentik-blueprints` literal, since
`helmrelease.yaml` references it by that fixed name) sourcing all 19 files
from `blueprints/`. Verified byte-identical output: built the ConfigMap
before and after removing `blueprintconfigmap.yaml`, diffed every `data`
key programmatically against the pre-refactor extraction - zero
mismatches.
