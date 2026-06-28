# Runbook: Which VM Is Causing RBD IO?

## Goal

Identify the VM behind hot RBD image or VM disk IO.

## Steps

1. Open the Ceph client IO by pool/image dashboard.
2. Sort RBD images by read/write throughput and ops.
3. Join image to Proxmox VM disk using `homelab_proxmox_vm_disk_info`.
4. Confirm VM disk IO in the Proxmox VM IO dashboard.
5. Check VM placement and Proxmox host pressure.
6. If the VM is a Kubernetes node, continue with [Which Kubernetes pod is causing VM disk IO?](which-kubernetes-pod-is-causing-vm-disk-io.md).

## Mitigation

- Pause workload inside the VM.
- Throttle backup, restore, compaction, or batch workload.
- Migrate the VM only if host-local pressure is the issue.
- Avoid blind migration during Ceph instability.

## Useful PromQL

```promql
topk(20,
  sum by (pve_node, vmid, vm_name, disk, pool_name, image) (
    rate(proxmox_vm_disk_write_bytes_total[5m])
    * on (pve_node, vmid, disk) group_left(pool_name, image)
      homelab_proxmox_vm_disk_info
  )
)
```

