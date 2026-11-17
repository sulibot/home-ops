# Renovate review — 2026-11-17

Reviewed all 100 Renovate PRs present at the start: 78 merged, 14 closed as obsolete or superseded, 8 retained for targeted follow-up. Eight more Renovate PRs appeared during review: #555 and #564–567 merged; #556–558 closed as individual Flux controller bumps. Total reviewed: 108; 83 merged, 17 closed, 8 held. Cilium #476 was subsequently rolled back. Existing unrelated non-Renovate PRs were not merged.

## Compatibility changes

- PR #553: fix Matter backup read permissions with DAC_READ_SEARCH, retaining a read-only data mount; explicitly preserve Homepage Kubernetes discovery token; keep HA bootstrap Python on 3.14; exclude `_archive` and `tmp` manifests from Renovate.
- PR #554: upgrade the complete Flux distribution on cluster-101 only. Cluster-104 remains on its existing bundle because Kubernetes 1.34.1 is below Flux 2.10's supported minimum. Upgrade standalone Python services, retaining HA's matching runtime. Set Matter's IPv6 listener explicitly and configure Authentik's trusted cluster proxy networks.
- HA, Music Assistant and Matter received fresh pre-upgrade Kopia backups. The initial Matter backup failed on repair-backups permissions; the corrected backup completed before the Matter upgrade.
- Matter 1.6 initially listened only on IPv4 and failed IPv6 probes. LISTEN_ADDRESS=:: restored readiness; the setting is committed in both Matter manifests.
- External DNS on cluster-104 recovered after the rollout and a Helm reconciliation reset.
- Stale CI failures on Zigbee2MQTT, Ceph CSI and app-template were refreshed against main and passed before merging.
- app-template 5 values were rendered for the affected live applications, including Homepage, Gatus and 1Password. Homepage retains its required API token; HA retains its explicit no-token policy.
- Fluent Bit 5.2 passed isolated --dry-run jobs against all four existing event/log configurations before merging; host/PVC state mounts were replaced with temporary empty directories in validation jobs.
- Paperless had zero documents and no pre/post consume scripts before its major upgrade.
- Valkey chart 6 retained StatefulSet selector, serviceName, volumeClaimTemplates and podManagementPolicy in comparison renders.
- GitHub Actions changes were reviewed for behavior compatibility. The CLI lacked workflow scope, so those merges used the connected GitHub application. upload-artifact's workflow has no automatic CI trigger; its change was reviewed directly.

## Rollout repairs

- #559 rolls Cilium back to 1.19.6 after 1.20.4 broke gateway traffic despite Ready agents. #560 prevents another automatic 1.20 upgrade pending investigation.
- #560 enables ARC CRD replacement on chart installation/upgrades; installed 0.15.1 CRDs now include listenerConfig. The controller was restarted to refresh its schema cache.
- Worker image caches filled during simultaneous image downloads. Removed only unused cached image references, retaining images referenced by current pods; application PVCs were untouched.
- Descheduler was temporarily paused after it evicted 32 pods during disk pressure. #561 protects owners with fewer than two replicas and limits each cycle to three evictions total, one per node.

- #562 allows the completed database-readiness Job to be recreated when its image changes. The new check completed successfully.
- #563 removes Collabora’s obsolete shell startup override for its distroless image, preserving allowed embedding sites through the supported content_security_policy variable. It also allows recreation of Vikunja’s idempotent bootstrap Job.
- #568 uses Recreate for Supabase storage’s single-attach PVC, avoiding a rolling-update attachment deadlock. Vikunja bootstrap uses Never restart policy to retain failed-attempt diagnostics; its rerun confirmed the existing admin.
- Aurral was recreated after a transient telemetry-webhook outage left its injection container absent. The replacement included instrumentation and became healthy.
- Flux source-controller was restarted on a healthy worker after its checkout failed on the full worker. All worker disk-pressure conditions cleared. No application volumes were deleted.

## Updates intentionally not merged

| PR | Update | Concrete reason / required next step |
| --- | --- | --- |
| #504 | SoulSync 3.6.6 | The running 2.8.9 service has persistent data. The proposed image exists, but the expected upstream GitHub repository/release could not be retrieved; verify the v3 migration contract and test a restored copy before changing the production database. |
| #506 | OpenCloud 9.1 | Releases change search-index schema and can refuse startup on incompatible existing indexes. Prepare/test the supported reindex migration; 7.5 is already merged. |
| #507 | n8n 3.3 | There are 10 workflows, 8 active, using code, webhook, schedule and email nodes. v3 changes runtime/security behavior and removes nodes; inspect the v3 migration report and test these workflows before enabling the new runtime. 2.49 is already merged. |
| #511 | Tempo 3.1 / chart 3.2 | Requires the 2-to-3 configuration migration; old ingester/compactor blocks are removed and upstream documents no supported downgrade. Validate a migrated configuration and retained trace data before upgrading; chart 2.4 is merged. |
| #514 | Sonarr 5.0.0.2941 | Upstream marks this release prerelease. Retain stable Sonarr 4; revisit when a stable 5 release is available. |
| #521 | Twenty 2.59 | Changes encryption/session handling and database migration behavior across major versions. Validate encryption keys and migration on a restored database; 1.23.9 is already merged. |
| #522 | OCI provider 9 | Jumps from provider 6 across multiple major versions and drops the lower version bound. Existing CI does not plan these cloud directories. Require a reviewed plan against the actual OCI state before merging. No Terraform apply ran. |
| #525 | Google provider 8 | Changes the provider for the GCS state-backend bootstrap and drops its lower bound. Require a reviewed plan with the existing bootstrap state/credentials before merging. No backend/IAM apply ran. |

Primary references: [Tempo migration](https://grafana.com/docs/tempo/latest/set-up-for-tracing/setup-tempo/upgrade/), [Sonarr prerelease](https://github.com/Sonarr/Sonarr/releases/tag/v5.0.0.2941), [Authentik release](https://docs.goauthentik.io/docs/releases/2026.8).

## PR accounting

Merged: #408, #411, #413, #414, #415, #416, #418, #419, #420, #421, #422, #430, #431, #432, #433, #434, #435, #436, #437, #438, #439, #440, #441, #442, #444, #445, #446, #447, #448, #449, #450, #451, #452, #453, #454, #455, #456, #457, #458, #459, #464, #465, #466, #467, #468, #469, #470, #472, #476, #477, #479, #480, #483, #484, #485, #486, #489, #490, #491, #492, #493, #494, #495, #498, #499, #500, #502, #505, #508, #509, #512, #513, #515, #516, #518, #520, #523, #524, #555, #564, #565, #566, #567.

Closed: #412, #426, #427, #428, #429, #471, #473, #474, #475, #478, #488, #501, #503, #519, #556, #557, #558.

Closed archive/scratch-only updates: #471, #474, #475, #478, #501, #503, #519. #412 is superseded by mise-action 5. #426–429 are individual Flux controller bumps superseded by coherent distribution management. #473 and #488 are partially superseded by compatibility-scoped PR #554.

## Deployment verification

At the verification checkpoint, all 104 main-cluster HelmReleases and all 6 Home Assistant cluster HelmReleases were Ready. All 5 Home Assistant cluster Kustomizations were Ready. The main cluster’s Kustomizations were still reconciling the final digest commits; all 134 Deployment/StatefulSet objects had their requested replica counts available at the checkpoint (including intentionally scaled-to-zero apps).

Verified Authentik 2026.8.5, n8n 2.49.0, Paperless 3.5.0, Supabase chart 0.8.0, all three ARC listeners, all three Valkey replicas, and the descheduler’s active singleton/burst protections. The API VIP /readyz returned ok and all nodes were Ready without DiskPressure. The eight migration/prerelease holds above remain open intentionally; Cilium remains on 1.19.6 after rollback.

Home Assistant remains 2026.11.1 with Eufy Clean Rooms 0.2.5; the RoboVac control patch was preserved. Fresh HA, Music Assistant and Matter backups completed, including a post-upgrade Matter backup using Kopia 0.23.1. No vacuum commands or automation changes were performed.

A merged update to an inactive/scaled-to-zero app is not evidence that its runtime migration has executed. No Terraform apply ran. Transient rollout errors were repaired; this review does not assert that every historical application log entry is error-free.
