# Runbook: Which Kubernetes Pod Is Causing VM Disk IO?

## Goal

Trace VM disk IO to Kubernetes pods, workloads, PVCs, and Ceph-backed volumes.

## Steps

1. Identify the hot VM and Kubernetes node from Proxmox mapping.
2. Open the Kubernetes workload IO by namespace/pod/PVC dashboard.
3. Filter by the Kubernetes node.
4. Sort pods by write/read bytes per second.
5. Join pod to PVC and PV.
6. Join PV to Ceph RBD image or CephFS subvolume.
7. Confirm the same image or subvolume appears hot in Ceph client IO metrics.

## Mitigation

- Pause the offending CronJob or backup.
- Scale down non-critical workloads.
- Apply application-level IO throttling.
- Cordon or drain only if node pressure is also present.

## Useful PromQL

```promql
topk(20,
  sum by (namespace, pod, persistentvolumeclaim, workload, workload_kind, node) (
    rate(container_fs_writes_bytes_total{pod!="",container!=""}[5m])
    * on (cluster, namespace, pod) group_left(persistentvolumeclaim, workload, workload_kind)
      homelab_kube_pod_pvc_info
  )
)
```

