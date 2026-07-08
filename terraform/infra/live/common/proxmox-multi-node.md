# Proxmox Multi-Node Terraform Pattern

The BPG Proxmox provider requires a concrete `node_name` for VM creation. For
multi-node clusters, keep node selection in Terraform inputs and make the drift
behavior explicit.

## VM node changes

Reusable VM modules set `migrate = true` by default. If `node_name` changes,
BPG should migrate the VM in place instead of replacing it.

Use this for normal Terraform-directed moves:

```hcl
proxmox = {
  node_name    = "pve02"
  datastore_id = "resources"
  vm_datastore = "rbd-vm"
  migrate      = true
}
```

## HA-managed VMs

If Proxmox HA is allowed to move a VM during maintenance or failover, Terraform
will see `node_name` drift. For HA-managed resources that should tolerate being
on any HA node, the VM resource needs:

```hcl
lifecycle {
  ignore_changes = [node_name]
}
```

Do not combine that with Terraform-driven migration for the same workload. Pick
one operating model per VM:

- Terraform-directed placement: keep `migrate = true`.
- HA-directed placement: ignore `node_name` drift and manage HA separately.

## Node-scoped resources

Provider resources such as files, downloads, certificates, DNS, hosts, time, and
Linux bridge/VLAN resources are node-scoped. Use one resource instance per node
when the object must exist on every node. For shared Ceph-backed datastores, one
file/download may be enough if Proxmox exposes it cluster-wide.
