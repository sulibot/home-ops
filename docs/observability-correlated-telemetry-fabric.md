# Correlated Telemetry Fabric

Status date: 2026-07-15

This cluster is moving toward a correlated telemetry model:

1. Alert or metric spike.
2. Dashboard filtered to namespace, workload, node, VM, or storage backend.
3. Related Kubernetes events.
4. Hubble flows, drops, and DNS.
5. Container, proxy, host, and storage logs.

The goal is not tracing-only observability. Traces are useful for instrumented apps and Beyla-discovered services, but most daily value should come from correlating metrics, logs, events, inventory, and network flows.

## Current Coverage

### Kubernetes

Covered:

- Prometheus, kube-state-metrics, node-exporter, cAdvisor, ServiceMonitor, PodMonitor, and PrometheusRule coverage.
- Kubernetes object and workload state through kube-state-metrics.
- Container logs through the cluster Fluent Bit daemonset into Loki.
- Kubernetes events through the `fluent-bit-events` pipeline into Loki.
- Hubble metrics and dashboards through `cilium-observability`.
- App-level auto-instrumentation through Beyla for Authentik and Plex.

Remaining gap:

- API server or kubelet reachability issues are now visible through events, Hubble, container logs, and Talos logs, but Talos service-health metrics are not exported as first-class metrics yet.

### Proxmox

Covered:

- PVE API metrics through `pve-exporter`.
- PVE node-exporter metrics from `pve01`, `pve02`, and `pve03`.
- Static scrape targets for Proxmox API and node-exporter in `proxmox-observability`.
- Proxmox visibility alerts in the cross-layer storage rule set.
- VM IO recording rules for top writer/reader workflows.
- PVE, FRR, corosync, kernel, and Ceph host logs through Ansible-managed rsyslog forwarding into `fluent-bit-infra`.

Remaining gaps:

- Proxmox VM disk to Ceph RBD image mapping is not exported yet.
- VM-to-Kubernetes node placement depends on labels or annotations consumed by `homeops-inventory-exporter`; missing labels reduce correlation quality.

### Ceph

Covered:

- Ceph manager Prometheus metrics from the Proxmox/Ceph nodes.
- Ceph health, OSD, MDS, recovery, and utilization alerting through the cross-layer storage rules.
- Ceph dashboards and SRE incident panels.
- Kubernetes PVC/PV/Ceph CSI relationships through `homeops-inventory-exporter`.
- Ceph OSD to Proxmox host, data device, DB LV, device class, and drive-bucket mapping through `homeops-inventory-exporter`.
- SMART and hardware-adjacent disk metrics through `smartctl-exporter`.
- Ceph daemon logs through the PVE host syslog forwarding path.

Remaining gaps:

- OSD serial and physical bay mapping is not exported.
- PG acting set mapping is not exported.
- Host kernel storage error metrics depend on the Proxmox node-exporter textfile collector being installed and healthy on each PVE node.

### Talos

Covered:

- Kubernetes sees Talos nodes as `Ready` and exposes node, kubelet, container, and workload metrics.
- Talos version and OS identity are visible through node metadata and node-exporter OS metrics.
- Talos service and kernel logs are configured in the Talos machine config module and received by the local `fluent-bit-infra` host-network DaemonSet on each node.
- Manual Talos operations are documented in the Talos runbook.

Remaining gaps:

- Talos machine health and per-service state are not exported as first-class Prometheus metrics.
- Talos logs require the Terraform Talos config change to be applied to nodes before they appear in Loki.

Talos coverage is worth adding. It is the layer that explains many Kubernetes symptoms: kubelet stalls, containerd issues, CNI setup failures, API server latency, disk pressure, time sync, and control-plane service failures.

### Cluster 104

Covered from the primary cluster-101 observability plane:

- Gatus synthetic checks for the cluster-104 Kubernetes API, internal Gateway,
  tunnel Gateway, Hubble metrics, Home Assistant, Home Assistant dashboard, and
  Music Assistant.
- Gatus endpoint failures for `cluster-104` and `cluster-104-apps` feed the
  normal PrometheusRule/Alertmanager path on cluster-101.
- A repo-owned `SRE Home Control Health` Grafana dashboard focuses on Home
  Assistant, the HA dashboard path, Music Assistant, cluster-104 Hubble
  drops/flow verdicts, home-control logs, and Kubernetes events.
- Cluster-104 Hubble metrics are exposed through `hubble-104.sulibot.com` and
  scraped by cluster-101 Prometheus through a `ScrapeConfig`.
- Cluster-104 home-control app logs and Kubernetes events are forwarded to
  cluster-101 Loki by a lightweight Fluent Bit pair in the `log-forwarding`
  namespace. The forwarders wait for `https://loki.sulibot.com/ready` before
  starting, so they do not spin noisily while the primary Loki Gateway route is
  unavailable.

Covered from cluster-104 itself:

- A lightweight `gatus-observer` deployment in the `observer` namespace checks
  cluster-101 API VIP reachability, cluster-101
  Grafana/Prometheus/Alertmanager/status surfaces,
  Proxmox APIs, RouterOS API reachability, Internet DNS reachability, and the
  local cluster-104 API/Gateways/Hubble/home-control services.
- The observer is intentionally local-only for now. It provides a small status
  UI on cluster-104 when cluster-101 monitoring is degraded; primary alerting
  for cluster-104 still lives in cluster-101.
- Live status on 2026-07-15: `observer-104.sulibot.com` reports 19/19 checks
  up, including Home Assistant, the Home Assistant dashboard path, Music
  Assistant, Matter Server, OTBR, and Hubble metrics.

Remaining gaps:

- Cluster-104 does not run a second Prometheus or log stack by design. It is a
  backup observer, not an independent full telemetry store.
- Direct cluster-104-originated paging is not enabled yet. The existing
  Alertmanager token material is not accepted by Gatus' Pushover provider, so
  add a dedicated valid token before enabling local observer notifications.
- Cluster-101 does not yet scrape cluster-104 kubelet, node, or Talos service
  metrics. Add those only if synthetic checks, Hubble metrics, logs, and events
  are not enough to identify home-control failures quickly.
- The updated cluster-101 Gatus checks, Loki Gateway route, Prometheus
  `ScrapeConfig`, and Grafana dashboard cannot be applied live while the
  cluster-101 API server reports `etcd` and `etcd-readiness` failures.

## Grafana Dashboard Review

Repo-owned dashboards are intentionally small:

- `SRE Executive Cluster Health`: keep as the daily cluster/PVE/Ceph glance.
- `SRE Incident Drill-Down`: keep as the cross-layer incident response board.
- `SRE Home Control Health`: added for the daily Home Assistant/Music Assistant
  workflow on cluster-104.

Imported dashboards are still useful and should stay enabled where the backing
component exists: Fluent Bit, Hubble, Cloudflare tunnels, Grafana operator,
VPA, Proxmox via Prometheus, Ceph, CloudNativePG, Valkey, Kubernetes,
node-exporter, Prometheus, RouterOS, and VolSync. KEDA, smartctl, and Spegel
remain disabled/commented in repo, which is the right posture until those
boards answer an active workflow.

## Immediate Findings

The PVE/Ceph metric design is good enough for first-pass incident attribution: host, VM, Ceph health, recovery, OSD, disk, and Kubernetes workload signals exist.

It is now enough for first-pass root-cause tracing back to PVE/Ceph without immediately shelling into hosts: metrics, host logs, Ceph daemon logs, and OSD device joins are all represented in the correlated path. VM disk to RBD and PG acting-set joins remain follow-up work.

The live observability plane showed control-plane/API latency during this review. Kubernetes events reported repeated pod sandbox creation failures where Multus timed out talking to the Kubernetes API service. That is a strong signal to add Talos and PVE host logs, because the current stack shows the symptom but not the lower-level cause.

## Gap Closure Order

1. Keep the telemetry plane itself healthy.
   Remove unsupported or invalid chart config, keep longer Helm timeouts for heavy observability releases, and alert when Prometheus, Loki, or Fluent Bit are not ready.

2. Add Talos log coverage. Done in repo.
   The Talos config module now supports service and kernel log forwarding, and cluster-101 enables local TCP JSON log delivery to `fluent-bit-infra`.

3. Add Proxmox host log coverage. Done in repo.
   The PVE baseline playbook now includes rsyslog forwarding to the `fluent-bit-infra` LoadBalancer receiver.

4. Expand inventory joins. Partially done.
   Ceph OSD to host/device/DB mapping is exported. Proxmox VM disk to RBD image mapping and Kubernetes node label enforcement remain.

5. Tighten Hubble correlation. Done in repo.
   Flow/drop/DNS panels are first-class in the SRE incident drilldown dashboard.
   Cluster-104 Hubble metrics are also exposed through the internal Gateway and
   added to the home-control dashboard.

6. Keep Beyla first-class for daily apps. Done in repo.
   Authentik and Plex are good first targets because they are used daily and can prove whether auto-discovered HTTP metrics/traces are useful before broader rollout.

## Answer

PVE and Ceph metrics are mostly covered, and PVE/Ceph host logs are now wired into Loki through `fluent-bit-infra`.

Talos coverage is still partial, but the main log gap is addressed in code. Talos-native service metrics remain a follow-up.

The biggest remaining gaps are VM disk to RBD mapping, Ceph PG acting-set mapping, OSD serial/bay enrichment, and optional Talos service-state metrics.

Cluster-104 is now covered in two layers: cluster-101 has the primary view of
its API/Gateway/app/Hubble/log/event surfaces in repo, while cluster-104 carries
a small independent observer for when the primary observability plane itself is
suspect. The cluster-104 observer and Hubble route are live; cluster-101-side
dashboard, Loki, Prometheus, and primary Gatus updates are waiting on the
cluster-101 etcd readiness issue before they can be applied.
