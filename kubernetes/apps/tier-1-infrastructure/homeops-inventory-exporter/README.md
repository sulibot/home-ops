# homeops-inventory-exporter

Small read-only Prometheus exporter for Kubernetes inventory joins.

## Purpose

This exporter turns Kubernetes API object relationships into stable `*_info` metrics so Grafana and PromQL can answer cross-layer questions without manual shell joins.

It currently exports:

- `homeops_kube_node_vm_info`
- `homeops_kube_pod_pvc_info`
- `homeops_kube_pvc_pv_info`
- `homeops_kube_pv_ceph_info`
- `homeops_pve_host_info`
- `homeops_ceph_osd_device_info`

## Scope

Current scope covers Kubernetes API inventory plus static PVE/Ceph host inventory:

- Nodes.
- Pods.
- PVCs.
- PVs.
- CSI fields from PV specs.
- PVE host service addresses.
- Ceph OSD data device, DB LV, host, class, and drive-bucket mapping.

Future scope can add:

- Proxmox VM disk to RBD image mapping.
- PG acting set mapping.

Do not add high-cardinality data such as per-file paths, per-RADOS-object data, or every Kubernetes label.

## Maintenance Notes

- Keep this exporter read-only.
- Keep labels stable and low-cardinality.
- Prefer explicit mapping metrics over clever PromQL.
- Add new metrics only when a dashboard, alert, or runbook uses them.
- If this grows beyond a few Kubernetes/Proxmox/Ceph collectors, split collectors into separate modules or move to a built image.

## Validation

```bash
kustomize build kubernetes/apps/tier-1-infrastructure/homeops-inventory-exporter/app
```
