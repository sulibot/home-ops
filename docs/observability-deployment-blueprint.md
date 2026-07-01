# Observability Deployment Blueprint

This is the practical target shape for everyday SRE visibility in home-ops. The goal is not to collect everything; it is to make common failures visible, correlated, and quiet until action is needed.

## Target Stack

| Function | Recommended component | Repo status | Why |
|---|---|---|---|
| Metrics and alert evaluation | Prometheus via kube-prometheus-stack | Present: `kubernetes/apps/tier-1-infrastructure/kube-prometheus-stack/` | Best fit for Kubernetes, exporters, rules, Alertmanager, and Grafana dashboards. |
| Dashboards | Grafana Operator | Present: `kubernetes/apps/tier-1-infrastructure/grafana/` | One visual front door for cluster, app, Ceph, Proxmox, disk, network, and incident views. |
| Logs | Victoria Logs | Present: `kubernetes/apps/tier-1-infrastructure/victoria-logs/` | Already deployed, simple, efficient. Do not add Loki unless Victoria Logs cannot support a required workflow. |
| Log collection | Fluent Bit | Present: `kubernetes/apps/tier-1-infrastructure/fluent-bit/` | Good low-overhead node log collector with filtering already in place. |
| Alert routing | Alertmanager | Present through kube-prometheus-stack | Keeps page-worthy alerts separate from warnings and daily review items. |
| Kubernetes state | kube-state-metrics, kubelet/cAdvisor | Present through kube-prometheus-stack | Workload, pod, PVC, node, and resource-pressure visibility. |
| Proxmox visibility | Proxmox exporter | Present: `kubernetes/apps/tier-1-infrastructure/proxmox-observability/` | VM placement and host/VM pressure. |
| Disk health | smartctl-exporter | Present: `kubernetes/apps/tier-1-infrastructure/smartctl-exporter/` | SMART/NVMe evidence before disks become mysterious Ceph latency. |
| Network device health | snmp-exporter and blackbox-exporter | Present | Switch/router/service reachability and network symptoms. |
| Missing correlation | homeops inventory exporter | Needed | Exports pod/PVC/PV/RBD/VM/host/OSD/disk join tables. This is the highest-value missing piece. |

Use Victoria Logs instead of adding Loki right now. Loki is fine, but adding it would duplicate the log backend, increase operations cost, and create two places to look. The SRE-friendly move is to make the existing log stack easier to query from Grafana.

## What SREs Should See First

Grafana should open to an "Executive Cluster Health" dashboard with seven rows:

1. **Is anything user-impacting?**
   - App availability probes.
   - Gateway/HTTPRoute probe failures.
   - Top application error rates from logs.
   - Current critical alerts.

2. **Is data safe?**
   - Ceph health.
   - OSD down/out.
   - Degraded, undersized, inactive, stale, remapped PGs.
   - Recovery/backfill active.

3. **Is storage slow or busy?**
   - Ceph client read/write throughput.
   - Ceph recovery/backfill throughput.
   - Top pods by filesystem write/read.
   - Top VMs by disk IO.
   - Top physical disks by busy time.

4. **Is the problem localized?**
   - Kubernetes node pressure.
   - Proxmox host pressure.
   - Disk/NIC errors by host.
   - Repeated alerts by host.

5. **What changed recently?**
   - Flux reconciliation failures.
   - Pod restarts.
   - OSD/MDS restarts.
   - Kernel disk/NIC error logs.

6. **What is noisy but not urgent?**
   - Top log talkers.
   - Warning alerts.
   - PVC growth.
   - Prometheus/Victoria Logs capacity.

7. **Where do I click next?**
   - Links to Ceph safety, Kubernetes workload IO, Proxmox VM IO, hardware health, and incident drill-down dashboards.

## Dashboard Set

### 1. Executive Cluster Health

Audience: daily operator glance.

Show:

- Critical alerts by layer.
- Ceph health and data safety.
- Kubernetes node readiness and pressure.
- Proxmox host up and resource pressure.
- Top IO producers: pod, VM, disk.
- Hardware red flags: SMART critical, media errors, NIC drops.
- Log error rate for infra namespaces.

Noise policy:

- No per-pod table unless sorted top 10.
- No debug/info log panels.
- No one-off transient warnings unless they persist.

### 2. Incident Drill-Down

Audience: active incident response.

Variables:

- `namespace`
- `pod`
- `node`
- `vmid`
- `pve_node`
- `pool`
- `image`
- `osd`
- `device`

Show:

- Alert timeline.
- Pod -> PVC -> PV -> RBD/CephFS mapping.
- Pod -> node -> VM -> Proxmox host mapping.
- RBD/pool IO and Ceph recovery.
- OSD latency and disk health.
- Kernel/Ceph/kubelet logs filtered to the same host/node/time window.

This dashboard becomes truly powerful after the inventory exporter exists.

### 3. Ceph Data Safety and Recovery

Audience: storage response.

Show:

- PG state counts.
- OSD up/in.
- Recovery/backfill bytes and objects.
- Client IO versus recovery IO.
- Scrub/deep-scrub activity.
- OSD apply/commit latency.
- OSD/device mapping table.
- Ceph logs: slow request, backfill, recovery, scrub, MDS crash.

Alert only on safety or stuck progress. Show recovery throughput on dashboards and reports; do not page just because recovery is active.

### 4. Kubernetes Workload IO

Audience: app and platform response.

Show:

- Top namespaces by IO.
- Top workloads by IO.
- Top pods by IO.
- PVC and storageclass mapping.
- Node placement.
- Node pressure.
- CSI operation errors.

Alert only when high IO is sustained and either recovery is active, node pressure exists, or workload exceeds an explicit baseline/limit.

### 5. Proxmox VM and Host IO

Audience: virtualization response.

Show:

- Top VMs by disk read/write.
- VM placement by Proxmox host.
- Host CPU, memory, disk, network pressure.
- VM disk backend mapping to RBD image.
- VM network throughput and drops.

Page only when a Proxmox host is exhausted or VM IO is contributing to storage safety/performance issues.

### 6. Physical Hardware Health

Audience: maintenance planning and root cause.

Show:

- SMART/NVMe critical warnings.
- SMART/NVMe counter deltas.
- Media errors.
- Disk busy time.
- Disk temperature.
- SATA/NVMe/kernel errors from logs.
- NIC drops/errors/link changes.
- Firmware/BIOS inventory.
- Repeated offender table by host, slot, disk serial, NIC PCIe slot.

Page on critical disk health and new SATA/FPDMA/ATA/NVMe kernel storage errors. Keep temperature and wear warnings as warning/report unless they cross hard thresholds.

### 7. Observability Platform Health

Audience: SRE keeping the eyes open.

Show:

- Prometheus scrape health.
- Prometheus storage forecast.
- Alertmanager health.
- Grafana health.
- Victoria Logs storage and ingestion.
- Fluent Bit output errors, retries, dropped records.

If observability is down, incident response is degraded. These alerts should be quiet but real.

## Alerting Policy

Use four classes:

| Class | Pages? | Examples |
|---|---:|---|
| Page | Yes | Ceph `HEALTH_ERR`, undersized/inactive PGs, OSD down causing data risk, SMART critical, Kubernetes node pressure affecting workloads. |
| Critical ticket | Usually no immediate wake-up | Persistent Ceph warning, stuck recovery, MDS metrics missing, Prometheus storage risk. |
| Warning | No | High pod IO, high VM IO, disk busy, NIC errors, PVC growth. |
| Report-only | No | Top talkers, daily capacity trend, recurring warning summary, firmware inventory changes. |

Rules of thumb:

- Recovery active is not an alert by itself.
- High IO is not an alert by itself.
- High IO during recovery is an alert.
- Disk busy is not a page unless paired with Ceph slow ops, SMART errors, or app impact.
- Logs should rarely page directly. Logs should enrich metric alerts.
- Every page must have a runbook link.
- Every warning should have a dashboard link or a report destination.

## Reporting Model

### Daily Report

Purpose: make slow degradation visible before it pages.

Include:

- Ceph health summary.
- Recovery/backfill/scrub time.
- Top 10 pods by write IO.
- Top 10 VMs by disk IO.
- Top 10 disks by busy time.
- SMART/NVMe new warnings.
- NICs with errors/drops.
- PVCs with fastest growth.
- Observability platform health.
- New or repeated warnings.

Delivery can be manual at first from Grafana snapshots or a scheduled script later.

### Weekly Review

Purpose: reduce alert noise and prevent repeat incidents.

Include:

- Alerts by count and duration.
- Alerts without action taken.
- New monitoring gaps found during incidents.
- Capacity forecasts.
- Repeated hardware or host patterns.
- Backup and restore verification status.

### Incident Report

Use [Incident Report Template](runbooks/incident-report-template.md).

Every incident should answer:

- What failed?
- What was impacted?
- Which layer started it?
- Which layer amplified it?
- What was paused, throttled, migrated, repaired, or rolled back?
- What signal was missing?

## Missing Piece: Inventory Exporter

The biggest improvement is not another dashboard. It is a small exporter that produces stable join metrics:

```text
homeops_kube_node_vm_info{node="k8s-worker-02",vmid="202",vm_name="k8s-worker-02",pve_node="pve03"} 1
homeops_proxmox_vm_disk_info{vmid="202",disk="scsi0",pool="vmpool",image="vm-202-disk-0"} 1
homeops_kube_pod_pvc_info{namespace="db",pod="postgres-0",node="k8s-worker-02",persistentvolumeclaim="pgdata-postgres-0",workload="postgres",workload_kind="StatefulSet"} 1
homeops_kube_pv_ceph_info{persistentvolume="pvc-abc",driver="rbd.csi.ceph.com",pool="k8s-rbd",image="csi-vol-abc"} 1
homeops_ceph_osd_device_info{osd="3",host="pve02",device="/dev/disk/by-id/ata-XYZ",serial="XYZ"} 1
```

Without these join metrics, SREs can see symptoms. With them, SREs can see the story.

## What Not To Add Yet

- Do not add Loki while Victoria Logs is working.
- Do not add tracing for this storage incident class until metrics/logs are solid.
- Do not add high-cardinality per-file CephFS metrics.
- Do not page on every high IO workload.
- Do not build dozens of dashboards before the correlation labels exist.
- Do not duplicate disk health alerts in multiple places unless Alertmanager suppresses them.

## Implementation Order

1. Keep and harden the current stack:
   - kube-prometheus-stack.
   - Grafana.
   - Victoria Logs.
   - Fluent Bit.
   - Proxmox exporter.
   - smartctl-exporter.
   - SNMP and blackbox exporters.
2. Add the cross-layer recording and alert rules.
3. Add the inventory exporter.
4. Build the Executive Cluster Health and Incident Drill-Down dashboards.
5. Add daily report generation from Prometheus/Grafana.
6. Tune alerts after two weeks of actual firing behavior.
