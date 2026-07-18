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
| sre | SRE Network and CNI Health | `sre-network-cni-dashboard-configmap.yaml` | Cilium/Hubble flow health, drops, API-service symptoms, waiting pods, and CNI logs. |
| sre | SRE Storage Ceph and PVC Health | `sre-storage-ceph-pvc-dashboard-configmap.yaml` | Ceph health, PG/OSD status, pool usage, CSI errors, PVC state, and storage logs. |
| sre | SRE PVE Hardware and Talos Signals | `sre-pve-hardware-dashboard-configmap.yaml` | Proxmox API, PVE guests, NVMe temperature/wear/errors, board sensors, and Talos host logs. |
| sre | SRE App Experience | `sre-app-experience-dashboard-configmap.yaml` | Gatus user-impact probes, Beyla RED, app logs, Valkey, and CloudNativePG. |
| sre | SRE Datastore Health | `sre-datastore-health-dashboard-configmap.yaml` | First-class Valkey and CloudNativePG health using live `redis_*` and `cnpg_*` metrics. |
| sre | SRE LGTM Telemetry Pipeline | `sre-telemetry-pipeline-dashboard-configmap.yaml` | Prometheus, Loki, Tempo, Fluent Bit, Beyla, exemplars, target health, and observability logs. |
| network | Router (MikroTik) | `router-dashboard-configmap.yaml` | CPU/thermal, per-interface throughput (top 10), errors/drops/collisions, link status, DHCP leases. Rebuilt 2026-07-18 - SNMP was actually reachable again (README's "SNMP targets time out" note was stale for the router). |
| network | Synthetic Probes | `synthetic-probes-dashboard-configmap.yaml` | Blackbox LAN + VPN/WAN probe status table and latency trend - "is it the network" before digging into an app. |
| platform | Inventory Joins | `inventory-joins-dashboard-configmap.yaml` | homeops-inventory-exporter cross-layer joins: k8s node -> PVE host, PVC -> PV -> Ceph FS, OSD -> physical device. Closes the ENG-16 "workload -> storage backend" and "node -> host" gap. |

## Folder Taxonomy

Reorganized 2026-07-18 in two independent passes that landed together: a
live-validation pass replaced most stale/no-data imports with new repo-owned
`sre`-folder dashboards, and a coverage-gap audit added three new
non-SRE dashboards plus fixed folder-assignment bugs (`keda`,
`smartctl-exporter`, `external-secrets` had no `spec.folder` key at all,
landing silently in Grafana's default folder despite this README claiming
otherwise).

| Folder | Scope | Boards |
|---|---|---|
| sre | Cross-layer incident workflows (this directory, 11 boards) | executive, workload-triage, incident-drilldown, home-control, loki-logs-explorer, network-cni, storage-ceph-pvc, pve-hardware, app-experience, datastore-health, telemetry-pipeline |
| network | Connectivity: DNS/tunnel, LAN/WAN reachability, router | cloudflare-tunnels, router-mikrotik, synthetic-probes |
| storage | Disk health (Ceph itself now lives in `sre-storage-ceph-pvc`) | smartctl-exporter |
| platform | Cluster plumbing / cross-cutting reference | vpa-overview, keda, external-secrets, inventory-joins |

Owner dirs (imports still live next to the component that owns them):
`cloudflare-tunnel/app/`, `smartctl-exporter/app/`, `grafana/app/`, `keda/app/`,
`external-secrets/app/` (tier-0-foundation).

`cluster`, `virtualization`, and `databases` folders are now empty - their
imports (`kubernetes-*`, `node-exporter-full`, `hubble`, `proxmox-via-prometheus`,
`ceph-clusters-overview`, `valkey`, `cloudnative-pg`, `volsync`) were removed
2026-07-17/18 as stale/no-data; the same ground is now covered by the new
`sre-network-cni`, `sre-storage-ceph-pvc`, `sre-pve-hardware`, and
`sre-datastore-health` dashboards, built against live-validated metric names.

### Deliberately not dashboarded

- **istio / kiali**: Kiali already ships its own dedicated mesh UI (service graph,
  traffic, health) - a Grafana import would duplicate it per the anti-pattern rule
  below, not add cross-layer correlation. Revisit only if a workflow needs mesh
  metrics correlated with logs/traces in the SRE dashboards specifically.
- **echo, gatus, descheduler self-monitoring**: scraped but intentionally left
  off dashboards - same reasoning as the removed `spegel`/`fluent-bit` self-monitoring
  boards. Gatus results belong on the SRE Executive board as an alert-adjacent
  signal, not a standalone board; not yet wired in.

Removed (2026-07-17): `prometheus`, `grafana-operator`, `fluent-bit`, `spegel` (component
self-monitoring that never answered an incident question), `kubernetes-namespaces`
(overlapped by the repo-owned SRE workflow dashboards), the original `routeros-mikrotik`
import (SNMP targets appeared dead at the time; rebuilt from scratch 2026-07-18, see below).

Removed (2026-07-17 live validation): `kubernetes-global`, `kubernetes-nodes`,
`kubernetes-pods`, `kubernetes-volumes`, `node-exporter-full`, `hubble`,
`proxmox-via-prometheus`, `ceph-clusters-overview`, `valkey`, `cloudnative-pg`,
`volsync`, `kubernetes-api-server`, and `kubernetes-coredns`. These imported
dashboards either required labels this cluster does not expose, used stale metric
names, had stale variables, or rendered as mostly no-data. Restore only as
repo-owned dashboards validated against live Prometheus/Loki labels.

## Operator Workflow

Use dashboards as workflow steps, not as a wall of graphs:

1. Start with `SRE Executive Cluster Health` for active alerts, user-impact probes, cluster pressure, and infrastructure red flags.
2. Use `SRE Workload Triage` to scope blast radius by cluster, namespace, workload, node, and network verdict.
3. Use Kubernetes event panels to find recent scheduling, image, sandbox, PVC, and probe failures.
4. Use Hubble flow/drop/DNS panels to distinguish app failure, DNS failure, policy drop, stale backend, and route failure.
5. Use `Loki Logs Explorer`, Grafana Explore, or Grafana Logs Drilldown for container, proxy, event, host, Talos, Proxmox, and Ceph logs.
6. Use `SRE Network and CNI Health` when the symptom is API-service timeout, Cilium/Multus churn, Hubble drops, DNS trouble, or a node-local blast radius.
7. Use `SRE Storage Ceph and PVC Health` when pods are stuck in mount, attach, PVC, CephFS, RBD, or CSI states.
8. Use `SRE PVE Hardware and Talos Signals` when VM host, NVMe temperature/wear, node sensors, Talos kubelet/CRI, or etcd logs might be causal.
9. Use `SRE App Experience` for the daily-service view: Gatus user impact, Beyla RED, app logs, Valkey, and Postgres.
10. Use `SRE LGTM Telemetry Pipeline` when the observability system itself looks suspect.
11. Confirm recovery in Gatus, alerts, workload readiness, Hubble drops, and logs, then leave the trail in Linear/runbooks.

## Keep / Fix / Remove

| Area | Decision | Notes |
|---|---|---|
| Repo-owned SRE dashboards | Keep/fix | They answer cross-layer workflows that imported dashboards do not. Keep them few. |
| Imported Kubernetes/node/Hubble/Proxmox/Ceph/Valkey/CNPG/VolSync dashboards | Remove/replace | Generic imports rendered mostly no-data or used stale labels; use repo-owned SRE dashboards instead. |
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
- Repo-owned LGTM dashboard collections now cover the intended workflow set:
  executive health, workload triage, logs explorer, network/CNI, storage/Ceph/PVC,
  PVE/hardware/Talos, app experience, incident drill-down, and telemetry pipeline.
- Correlation wiring: Prometheus exemplars -> Tempo (`exemplarTraceIdDestinations`),
  Tempo -> Loki via span-attribute/label tag join (`k8s.namespace.name`->`namespace`,
  `service.name`->`app`). Trace IDs do NOT appear in log lines; the join is
  label+time based until apps adopt OTel SDKs.
- Live validation found Prometheus metrics for Beyla (`http_server_*`), Hubble
  (`hubble_*`), CSI (`csi_operations_seconds_*`), Proxmox API
  (`pve_*`), Proxmox node/NVMe hardware (`node_hwmon_*`, `nvme_*`), Valkey
  (`redis_*`), CloudNativePG (`cnpg_*`), Gatus (`gatus_*`), Loki (`loki_*`),
  Tempo (`tempo_*`), Fluent Bit (`fluentbit_*`), and exemplars
  (`prometheus_tsdb_exemplar_*`).

Validated on 2026-07-15:

- Grafana is healthy on `12.3.3`; Loki is healthy on `3.7.3`; this supports the Grafana Logs Drilldown app.
- Loki has labels: `cluster`, `namespace`, `pod`, `service_name`, `stream`, `stream_class`, Kubernetes event labels, and `job`.
- Hubble metrics exist, including forwarded and dropped flows.
- Valkey metrics exist through `redis_*` exporter metrics.
- CloudNativePG metrics exist as `cnpg_*`; use those names rather than generic `postgres_*`.
- Gatus now uses curated repo-owned checks only. The noisy sidecar auto-discovery
  path was removed after it produced stale root-path checks for API-only
  services such as Loki.
- Ceph MGR target health exists, but live Ceph scrapes currently return zero
  Ceph samples (`scrape_samples_scraped{job="ceph-mgr-targets"} == 0`) and
  pve01/pve03 Ceph targets time out. Storage dashboards expose this as missing
  telemetry instead of blank Ceph capacity/latency charts.
- VolSync currently exposes no `volsync_*` metrics, so the imported VolSync
  dashboard was removed rather than kept as a mostly empty board.
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
