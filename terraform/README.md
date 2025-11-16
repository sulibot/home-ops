# Taskfile-Driven K8s Cluster Builder (Clusters 101–103)

This scaffold lets you build Kubernetes clusters end-to-end using **Taskfile** (no shell scripts), with the **same tasks** runnable locally and in **GitHub Actions**.

**Pipeline:** build custom Talos image → Terraform apply (Proxmox) → kubeadm bootstrap → Cilium → Flux → validate.

> ⚠️ Replace placeholder values marked with `CHANGE_ME` before running.
> The Terraform provider & variables assume Proxmox; adjust if needed.

## Quick Start
```bash
# List tasks
task --list

# Build cluster 101 with a fresh Talos image end-to-end
task build:all CLUSTER_ID=101

# Run only Terraform or only Ansible phase
task build:infra CLUSTER_ID=101
task build:cluster CLUSTER_ID=101

# Validate
task validate CLUSTER_ID=101

## Terragrunt Environments (experimental)

The `infra/` directory contains a Terragrunt-first layout:

```
infra/
├── modules/            # talos_image_factory + cluster_core (Talos image + VM orchestration)
├── live/
│   ├── common/         # shared proxmox credentials + globals + schematic defaults
│   └── cluster-101/    # cluster directory (named by cluster ID)
│       ├── image/      # builds & uploads Talos image
│       ├── nodes/      # provisions VMs (depends on image stack)
│       ├── cluster.hcl # cluster configuration (name, nodes, network)
│       └── image.hcl   # optional: override schematic for this cluster
└── terragrunt.hcl      # shared remote state + defaults
```

To apply the new stack:

```bash
# 1. Build/upload the Talos image
cd terraform/infra/live/cluster-101/image
terragrunt apply

# 2. Provision VMs using that image
cd ../nodes
terragrunt apply
```

## GitHub Actions
- CI runs `terraform fmt/validate/plan` on PRs.
- Manual `workflow_dispatch` can trigger `task build:all` (guarded; customize env/secrets).
