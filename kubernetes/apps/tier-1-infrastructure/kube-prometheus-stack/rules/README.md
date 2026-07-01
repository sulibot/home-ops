# Prometheus Rules

This directory contains repo-owned PrometheusRule resources for home-ops.

## Maintenance Rules

- Alerts must be actionable.
- Every page or critical alert needs a runbook link.
- High IO alone should not page.
- Recovery active alone should not page.
- High IO during recovery should alert.
- Hardware health faults should alert directly.
- Use recording rules for repeated expressions and dashboard panels.
- Tune thresholds after observing real firing behavior for at least one week.

## Cross-Layer Storage Rules

`prometheusrule-cross-layer-storage.yaml` provides the first SRE-focused storage rule set:

- Pod filesystem IO recording rules.
- Proxmox VM disk IO recording rules.
- Ceph recovery throughput recording rule.
- Disk busy and NIC error recording rules.
- Alerts for Ceph safety, slow ops, recovery contention, OSD state, MDS health details, Kubernetes node pressure, SMART/NVMe health, and Proxmox visibility.
- Predictor alerts for SATA/FPDMA/kernel storage errors, Ceph recent daemon crashes, scrub overdue conditions, OSD utilization variance, and SMART/NVMe counter deltas.

## Host Kernel Storage Error Metrics

SATA link resets, FPDMA errors, ATA exceptions, NVMe timeouts, block I/O errors, and PCIe AER events come from Proxmox host journals. They are exported through node_exporter textfile metrics installed by:

`ansible/lae.proxmox/roles/node_exporter`

The textfile metric is:

```text
homeops_host_kernel_storage_errors_total{host="pve01",category="fpdma_error"} 1
```

Categories:

- `sata_link_reset`
- `fpdma_error`
- `ata_exception`
- `io_error`
- `nvme_timeout`
- `pcie_aer`

## Noise Budget

Review this rule set weekly until it settles.

- Delete alerts that never lead to action.
- Downgrade alerts that are useful context but not urgent.
- Promote alerts only when they have repeatedly predicted or accompanied real impact.
- Prefer dashboards and reports for trend signals.

Validation:

```bash
kustomize build --load-restrictor LoadRestrictionsNone kubernetes/apps/tier-1-infrastructure/kube-prometheus-stack/rules
```
