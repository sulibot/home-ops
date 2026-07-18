# SRE Dashboards

This directory contains repo-owned Grafana dashboards managed by the Grafana Operator.

## Maintenance Rules

- Keep dashboards few and purpose-built.
- Prefer one executive view and one drill-down view over many overlapping dashboards.
- A panel must answer an operational question, not merely show that a metric exists.
- Top-N tables should stay bounded to 10-15 rows.
- Do not add panels for debug/info logs.
- Do not duplicate imported dashboards unless the custom dashboard adds cross-layer correlation.
- If a panel is not used during incidents or weekly review, remove it.

## Current Custom Dashboards

| Folder | Dashboard | File | Purpose |
|---|---|---|---|
| sre | SRE Executive Cluster Health | `sre-executive-dashboard-configmap.yaml` | Daily glance: safety, pressure, top IO, hardware red flags, active alerts, logs. |
| sre | SRE Workload Triage | `sre-workload-triage-dashboard-configmap.yaml` | First responder view: all-services RED table (Beyla), then pivot into events, Hubble, logs, and infra telemetry. |
| sre | SRE Incident Drill-Down | `sre-incident-drilldown-configmap.yaml` | Active response: write IO versus recovery, Ceph safety, top pods/VMs/disks, alerts, logs. |
| sre | SRE Home Control Health | `home-control-dashboard-configmap.yaml` | Home Assistant, Music Assistant, cluster-104 Hubble flows, and related logs/events. |
| sre | Loki Logs Explorer | `loki-logs-explorer-dashboard-configmap.yaml` | Curated Loki entry points for events, infrastructure logs, workload logs, and cross-cluster log streams. |
| network | Router (MikroTik) | `router-dashboard-configmap.yaml` | CPU/thermal, per-interface throughput (top 10), errors/drops/collisions, link status, DHCP leases. Rebuilt 2026-07-18 - SNMP was actually reachable again (README's "SNMP targets time out" note was stale for the router). |
| network | Synthetic Probes | `synthetic-probes-dashboard-configmap.yaml` | Blackbox LAN + VPN/WAN probe status table and latency trend - "is it the network" before digging into an app. |
| platform | Inventory Joins | `inventory-joins-dashboard-configmap.yaml` | homeops-inventory-exporter cross-layer joins: k8s node -> PVE host, PVC -> PV -> Ceph FS, OSD -> physical device. Closes the ENG-16 "workload -> storage backend" and "node -> host" gap. |

## Folder Taxonomy

Reorganized 2026-07-18 for coherence (was ad hoc; two dashboards had no
folder assigned at all due to a missing `spec.folder` key, landing silently
in Grafana's default folder despite this README claiming otherwise).

| Folder | Scope | Boards |
|---|---|---|
| sre | Cross-layer incident workflows (this directory) | executive, workload-triage, incident-drilldown, home-control, loki-logs-explorer |
| cluster | Kubernetes core | kubernetes-api-server, kubernetes-coredns, kubernetes-global, kubernetes-nodes, kubernetes-pods, kubernetes-volumes, node-exporter-full |
| network | Connectivity: mesh-external traffic, DNS/tunnel, LAN/WAN reachability | hubble, cloudflare-tunnels, router-mikrotik, synthetic-probes |
| storage | Disk/Ceph health | ceph-clusters-overview, smartctl-exporter (folder was unset - fixed) |
| virtualization | Proxmox | proxmox-via-prometheus |
| databases | Managed datastores | valkey, cloudnative-pg |
| platform | Cluster plumbing / cross-cutting reference | vpa-overview, volsync, keda (folder was unset - fixed), external-secrets (folder was unset - fixed), inventory-joins |

Owner dirs (imports still live next to the component that owns them):
`kube-prometheus-stack/app/`, `cilium-observability/app/`, `cloudflare-tunnel/app/`,
`proxmox-observability/app/`, `smartctl-exporter/app/`, `valkey/app/`,
`postgres-vectorchord/app/`, `grafana/app/`, `volsync/app/`, `keda/app/`,
`external-secrets/app/` (tier-0-foundation).

Removed (2026-07-17): `prometheus`, `grafana-operator`, `fluent-bit`, `spegel` (component
self-monitoring that never answered an incident question), `kubernetes-namespaces`
(fully overlapped by kubernetes-global + kubernetes-pods), the old `routeros-mikrotik`
import (rebuilt from scratch 2026-07-18, see above).

### Deliberately not dashboarded

- **istio / kiali**: Kiali already ships its own dedicated mesh UI (service graph,
  traffic, health) - a Grafana import would duplicate it per the anti-pattern rule
  below, not add cross-layer correlation. Revisit only if a workflow needs mesh
  metrics correlated with logs/traces in the SRE dashboards specifically.
- **echo, gatus, descheduler self-monitoring**: scraped but intentionally left
  off dashboards - same reasoning as the removed `spegel`/`fluent-bit` self-monitoring
  boards. Gatus results belong on the SRE Executive board as an alert-adjacent
  signal, not a standalone board; not yet wired in.

## Operator Workflow

Use dashboards as workflow steps, not as a wall of graphs:

1. Start with `SRE Executive Cluster Health` for active alerts, user-impact probes, cluster pressure, and infrastructure red flags.
2. Use `SRE Workload Triage` to scope blast radius by cluster, namespace, workload, node, and network verdict.
3. Use Kubernetes event panels to find recent scheduling, image, sandbox, PVC, and probe failures.
4. Use Hubble flow/drop/DNS panels to distinguish app failure, DNS failure, policy drop, stale backend, and route failure.
5. Use `Loki Logs Explorer`, Grafana Explore, or Grafana Logs Drilldown for container, proxy, event, host, Talos, Proxmox, and Ceph logs.
6. Use `SRE Incident Drill-Down` when storage, Proxmox, Ceph, or host hardware might be the cause.
7. Confirm recovery in Gatus, alerts, workload readiness, Hubble drops, and logs, then leave the trail in Linear/runbooks.

## Keep / Fix / Remove

| Area | Decision | Notes |
|---|---|---|
| Repo-owned SRE dashboards | Keep/fix | They answer cross-layer workflows that imported dashboards do not. Keep them few. |
| Imported Kubernetes/node/Prometheus dashboards | Keep | Useful for component detail after the SRE workflow identifies the layer. |
| Imported Hubble dashboard | Keep | Backing Hubble metrics are present and useful for network triage. |
| Imported Proxmox/Ceph dashboards | Keep but treat no-data as degraded telemetry | Live Proxmox API and Ceph MGR scrapes are currently down; dashboards must not be interpreted as healthy silence. |
| Curated Loki dashboard | Keep | Good for saved starting points, but daily ad-hoc browsing should use Explore or Logs Drilldown. |
| Empty/debug-only panels | Remove | A panel must answer an action-oriented question or expose missing telemetry clearly. |

## Current Live Gaps

Updated 2026-07-18 (dashboard coverage audit):

- **The router's SNMP scrape is up** (`up{job="snmp-exporter"} == 1`, mikrotik/if_mib/system
  modules all returning data) - the README's prior "SNMP targets time out" note was stale
  for the router specifically (APC/Dell UPS/iDRAC endpoints may still be down - not verified
  in this pass). Router dashboard rebuilt on real `mtxr*`/`ifHC*` metrics.
- **blackbox-exporter/vpn was never deployed** - its entire directory (helmrelease, probes)
  had no Flux Kustomization referencing it at all. `blackbox-exporter/lan`'s own `probes.yaml`
  was also missing from its kustomization's resource list. Both fixed 2026-07-18; `probe_success`
  had zero series cluster-wide before this.
- `keda`, `smartctl-exporter`, `external-secrets` dashboard CRs had no `spec.folder` set
  despite this README claiming folder placement for them - fixed.

Updated 2026-07-17 (correlation-loop rollout):

- Prometheus is stock `v3.11.0` (prompp fork removed) with `exemplar-storage`
  and the OTLP receiver enabled.
- Beyla instruments ~25 services; traces route through otel-collector to Tempo.
  The workload-triage board has an all-services RED table.
- Correlation wiring: Prometheus exemplars -> Tempo (`exemplarTraceIdDestinations`),
  Tempo -> Loki via span-attribute/label tag join (`k8s.namespace.name`->`namespace`,
  `service.name`->`app`). Trace IDs do NOT appear in log lines; the join is
  label+time based until apps adopt OTel SDKs.

Validated on 2026-07-15:

- Grafana is healthy on `12.3.3`; Loki is healthy on `3.7.3`; this supports the Grafana Logs Drilldown app.
- Loki has labels: `cluster`, `namespace`, `pod`, `service_name`, `stream`, `stream_class`, Kubernetes event labels, and `job`.
- Hubble metrics exist, including forwarded and dropped flows.
- Valkey metrics exist through `redis_*` exporter metrics.
- CloudNativePG metrics exist as `cnpg_*`; use those names rather than generic `postgres_*`.
- Gatus now uses curated repo-owned checks only. The noisy sidecar auto-discovery
  path was removed after it produced stale root-path checks for API-only
  services such as Loki.
- Proxmox API scrape targets return HTTP 500 from `pve-exporter`.
- Ceph MGR targets on `fd00:10::1-3:9283` refuse connections.
- SNMP exporter targets time out for the configured APC/Dell/RouterOS endpoints.
- Alertmanager Pushover notifications fail until `PUSHOVER_ALERTMGR` is populated with a valid application token in the shared `pushover` 1Password item.
- Alertmanager email notification was failing because it referenced a missing `default.message` template; the repo now uses an inline message template.
- Flux is reconciling `main`; `main` still contains an invalid AlertmanagerConfig weekday range until this branch is merged.

## Editing Workflow

1. Edit the dashboard in Grafana when layout work is easier visually.
2. Export the dashboard JSON.
3. Replace only the JSON block in the matching ConfigMap.
4. Keep panel titles short and operational.
5. Validate locally:

```bash
kustomize build --load-restrictor LoadRestrictionsNone kubernetes/apps/tier-1-infrastructure/grafana/dashboard
```

## Dashboard Anti-Patterns

- More than one screen of stat panels.
- Large unfiltered pod tables.
- Panels that require knowing obscure metric names to interpret.
- Alert panels without runbook links in the underlying alert rules.
- Log panels that show raw high-volume application logs by default.
- Adding another datastore or board without a specific workflow gap.
