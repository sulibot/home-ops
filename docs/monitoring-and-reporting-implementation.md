# Monitoring and Reporting Implementation

This document turns the cross-layer observability model into concrete home-ops monitoring and reporting artifacts.

## Monitoring Sources in This Repo

| Area | Repo location | Purpose |
|---|---|---|
| Prometheus, Alertmanager, kube-state-metrics, Grafana dashboards | `kubernetes/apps/tier-1-infrastructure/kube-prometheus-stack/` | Core metric and alert platform |
| Cross-layer storage alerts and recording rules | `kubernetes/apps/tier-1-infrastructure/kube-prometheus-stack/rules/prometheusrule-cross-layer-storage.yaml` | First implementation slice for pod, node, Ceph, disk, and NIC signals |
| Proxmox exporter | `kubernetes/apps/tier-1-infrastructure/proxmox-observability/` | Proxmox host and VM visibility |
| Kubernetes inventory exporter | `kubernetes/apps/tier-1-infrastructure/homeops-inventory-exporter/` | Pod/PVC/PV/Ceph CSI join metrics |
| SMART/device health | `kubernetes/apps/tier-1-infrastructure/smartctl-exporter/` | Disk and NVMe health |
| Logs | `kubernetes/apps/tier-1-infrastructure/victoria-logs/` and `kubernetes/apps/tier-1-infrastructure/fluent-bit/` | Cross-layer event and log correlation |
| SRE executive dashboard | `kubernetes/apps/tier-1-infrastructure/grafana/dashboard/sre-executive-dashboard-configmap.yaml` | First high-signal everyday operating console |
| SRE incident drill-down dashboard | `kubernetes/apps/tier-1-infrastructure/grafana/dashboard/sre-incident-drilldown-configmap.yaml` | Focused active-incident view for IO, Ceph, alerts, and logs |

## New Alert Coverage

The cross-layer storage rule file adds:

- `PodFilesystemWriteIOHigh`
- `KubernetesNodeDiskPressure`
- `KubernetesNodeMemoryPressure`
- `HostDiskBusy`
- `HostNetworkErrorsOrDrops`
- `HostKernelStorageErrors`
- `HostPCIeAERErrors`
- `SmartDeviceCritical`
- `SmartDeviceMediaErrors`
- `SmartDeviceMediaErrorsIncreased`
- `SmartDeviceAvailableSpareDecreased`
- `CephHealthError`
- `CephHealthWarnPersistent`
- `CephRecentDaemonCrash`
- `CephScrubOverdue`
- `CephOSDUtilizationVarianceHigh`
- `CephOSDDown`
- `CephMDSMetricsMissing`
- `CephRecoveryActiveWithHighPodWrites`

It also adds recording rules:

- `homeops:pod_fs_write_bytes:rate5m`
- `homeops:pod_fs_read_bytes:rate5m`
- `homeops:pod_workload_write_bytes:rate5m`
- `homeops:pod_workload_read_bytes:rate5m`
- `homeops:node_disk_io_time:rate5m`
- `homeops:nic_errors_drops:rate5m`
- `homeops:ceph_osd_used_ratio`
- `homeops:ceph_osd_used_ratio_variance`

Host kernel storage error counters are provided by the Proxmox `node_exporter` Ansible role through node_exporter textfile metrics:

```text
homeops_host_kernel_storage_errors_total{host="pve01",category="sata_link_reset"}
homeops_host_kernel_storage_errors_total{host="pve01",category="fpdma_error"}
```

These are intentionally conservative. The Kubernetes inventory exporter now provides pod/PVC/PV/Ceph CSI mapping metrics. The next implementation step is to extend the exporter with Proxmox VM disk to RBD image and Ceph OSD to physical disk mappings.

## Human Maintenance Contract

This observability stack should stay small enough for one operator to maintain.

- Keep two custom SRE dashboards until the inventory exporter exists: executive health and incident drill-down.
- Do not add a new dashboard when an existing one can gain one useful panel.
- Do not add an alert unless the expected operator action is clear.
- Delete or downgrade alerts that are only interesting in hindsight.
- Keep warning alerts routed to review/reporting paths, not page paths.
- Treat daily and weekly reports as noise drains: useful signals go there before they become alerts.
- Review alert history weekly for the first month after deployment.
- Keep runbook links current before promoting any alert to critical/page severity.

## Reporting Outputs

### Daily Storage and Platform Health Report

Audience: operator/SRE.

Frequency: daily.

Recommended sections:

- Ceph health: health status, OSD down/out count, recovery/backfill active time, degraded/undersized PGs.
- Top client IO: top pods, namespaces, VMs, and RBD images by read/write throughput.
- Hardware health: SMART critical warnings, media errors, hot devices, NIC errors/drops, disk busy alerts.
- Kubernetes health: node pressure, pod restarts, top PVC writers.
- Proxmox health: top VM IO and host pressure.
- Open incidents and unresolved follow-ups.

PromQL starting points:

```promql
topk(10, homeops:pod_fs_write_bytes:rate5m)
```

```promql
topk(10, homeops:pod_fs_read_bytes:rate5m)
```

```promql
topk(10, homeops:node_disk_io_time:rate5m)
```

```promql
topk(10, homeops:nic_errors_drops:rate5m)
```

```promql
ceph_health_status
```

### Weekly Reliability Review

Audience: repo owner and operators.

Frequency: weekly.

Recommended sections:

- Alert review: noisy alerts, missed incidents, alerts without runbooks.
- Capacity review: Ceph pools, Prometheus retention, Victoria Logs storage, Kubernetes PVC growth.
- Hardware trend review: SMART deltas, media errors, temperature, NIC errors, repeated host behavior.
- Recovery readiness: last backup verification, VolSync/Kopia restore checks, Ceph clean-state windows.
- Workload IO review: recurring high-write jobs, backup windows, databases, object/media services.

### Incident Report

Use [Incident Report Template](runbooks/incident-report-template.md).

Minimum required evidence:

- Alert names and firing windows.
- Impacted namespace/workload/pod/PVC.
- Impacted VM and Proxmox host if known.
- Impacted Ceph pool/image/OSD if known.
- Recovery/backfill/scrub status.
- Disk/NIC/kernel hardware evidence.
- Mitigations applied and rollback plan.

## Dashboard Reporting Model

Grafana dashboards should be organized into these folders:

- `cluster`: Kubernetes and node dashboards already sourced by kube-prometheus-stack.
- `infrastructure`: Proxmox, Ceph, SMART, NIC, and physical host dashboards.
- `incidents`: drill-down dashboards for active response.

Minimum dashboard set:

- Executive cluster health.
- Ceph recovery and data safety.
- Ceph client IO by pool/image.
- Proxmox VM IO by VM/disk/host.
- Kubernetes workload IO by namespace/pod/PVC.
- Physical disk/SATA/NVMe/NIC health.
- Incident drill-down.

The current repo already has imported Kubernetes, Proxmox, SMART, and observability dashboards. The custom dashboards above should be added after the mapping exporter exists, because the highest-value panels depend on stable cross-layer labels.

The first custom dashboard is now implemented as `SRE Executive Cluster Health`. It intentionally uses only high-signal panels:

- Ceph health.
- Critical/page alert count.
- Kubernetes node pressure.
- SMART/NVMe disk faults.
- NIC errors/drops.
- Client IO versus Ceph recovery.
- Top pod writers.
- Busiest physical disks.
- Firing alerts.
- Recent infrastructure error logs from Victoria Logs.
