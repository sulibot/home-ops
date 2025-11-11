# GitHub Actions CI/CD Pipeline

## Overview

This document describes the GitHub Actions-based CI/CD pipeline for automating Kubernetes cluster provisioning in your homelab infrastructure.

## 🎯 Goals

- **Automate end-to-end** Talos cluster provisioning (Terraform → VMs → Talos → K8s → Flux)
- **Self-hosted execution** with Proxmox API access
- **IPv6-first networking** with dual-stack support
- **Incremental adoption** without disrupting existing workflows
- **GitOps-native** integration with Flux CD
- **Immutable infrastructure** using Talos Linux

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Repository                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  Pull Request                         │  │
│  │                                                        │  │
│  │  terraform/live/clusters/cluster-101/                │  │
│  │  └── terragrunt.hcl (changed)                        │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│                 ▼                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Workflow: terraform-plan.yml                        │  │
│  │  - Checkout code                                      │  │
│  │  - Setup SOPS/Terraform/Terragrunt                   │  │
│  │  - Run: terragrunt plan                              │  │
│  │  - Comment plan output on PR                         │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│                 ▼                                            │
│         [Developer reviews plan]                             │
│                 │                                            │
│                 ▼                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │           Merge to main                               │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│                 ▼                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Workflow: cluster-provision-talos.yml               │  │
│  │                                                        │  │
│  │  Step 1: Terraform Apply                             │  │
│  │    └─> Provision VMs with Talos NoCloud image       │  │
│  │                                                        │  │
│  │  Step 2: Wait for VMs                                │  │
│  │    └─> Check Talos API responding                   │  │
│  │                                                        │  │
│  │  Step 3: Generate Talos Machine Configs             │  │
│  │    └─> talosctl gen config with IPv6 networking     │  │
│  │                                                        │  │
│  │  Step 4: Apply Talos Configurations                 │  │
│  │    └─> talosctl apply-config to all nodes           │  │
│  │                                                        │  │
│  │  Step 5: Bootstrap Kubernetes                        │  │
│  │    └─> talosctl bootstrap on first control plane    │  │
│  │                                                        │  │
│  │  Step 6: Configure RouterOS                          │  │
│  │    └─> Setup BGP peers for all nodes                │  │
│  │                                                        │  │
│  │  Step 7: Install Flux CD                             │  │
│  │    └─> Bootstrap Flux from GitHub                    │  │
│  │                                                        │  │
│  │  Step 8: Verify Health                               │  │
│  │    └─> Check Talos, etcd, nodes, VIP, pods          │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│                 ▼                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Cluster Ready for GitOps!                     │  │
│  │  Flux syncs apps from kubernetes/clusters/production │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 📂 Components

### GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `terraform-plan.yml` | PR to `main` | Validate Terraform changes, post plan as PR comment |
| `cluster-provision-talos.yml` | Manual dispatch | Provision Talos-based K8s cluster |
| `cluster-destroy.yml` | Manual dispatch | Safely tear down a cluster |
| `flux-validate.yml` | PR to `main` | Lint and validate Kubernetes manifests |

### Helper Scripts

Located in `.github/scripts/`:

| Script | Purpose |
|--------|---------|
| `provision-cluster-talos.sh` | Orchestrates entire Talos cluster lifecycle |
| `wait-for-vms.sh` | Waits for VMs to have Talos API responding |
| `configure-routeros.sh` | Configures BGP peering and static routes on RouterOS |
| `verify-cluster-health.sh` | Runs comprehensive post-provision health checks |

### Ansible Playbooks

New playbooks in `ansible/k8s/playbooks/`:

| Playbook | Purpose |
|----------|---------|
| `bootstrap-kubernetes.yml` | Initialize K8s with kubeadm, join nodes, label topology |
| `verify-cluster.yml` | Verify node health, BGP status, VIP reachability |

### Terraform Modules

| Module | Purpose |
|--------|---------|
| `terraform/modules/pve/routeros-config/` | Automated RouterOS BGP configuration (NEW) |

## 🚀 Usage

### Provision a Cluster via GitHub Actions

1. **Navigate** to Actions tab in GitHub
2. **Select** "Provision Cluster (Debian)"
3. **Click** "Run workflow"
4. **Configure**:
   - Cluster ID: `101`, `102`, etc.
   - Action: `plan` or `apply`
   - Options: Skip Flux, Skip Verify
5. **Run** and monitor logs

### Provision Locally

```bash
# Dry run to see what would happen
./.github/scripts/provision-cluster-debian.sh 101 plan

# Apply changes
./.github/scripts/provision-cluster-debian.sh 101 apply

# Apply without Flux
./.github/scripts/provision-cluster-debian.sh 101 apply --skip-flux

# Destroy cluster
./.github/scripts/provision-cluster-debian.sh 101 destroy
```

### Test Terraform Changes via PR

1. **Create** a feature branch
2. **Modify** `terraform/live/clusters/cluster-101/cluster.hcl`
3. **Push** to GitHub
4. **Open** PR
5. **Review** Terraform plan in PR comments
6. **Merge** to trigger provisioning (if workflow configured)

## 🔐 Prerequisites

### Self-Hosted Runner

The workflows require a self-hosted GitHub Actions runner with:

1. **Network Access**:
   - Proxmox API (HTTPS)
   - RouterOS API (HTTPS)
   - SSH to all cluster VMs

2. **Installed Tools**:
   ```bash
   # Core tools
   terraform >= 1.5
   terragrunt >= 0.50
   ansible >= 2.15
   kubectl >= 1.28
   flux >= 2.1

   # Utilities
   jq
   curl
   ssh
   ```

3. **Authentication**:
   - SSH keys for Ansible (in `~/.ssh/`)
   - Proxmox credentials (via SOPS)
   - GitHub token (for Flux bootstrap)

### GitHub Secrets

Configure these in **Settings → Secrets → Actions**:

| Secret | Description | Example |
|--------|-------------|---------|
| `SOPS_AGE_KEY` | Your SOPS Age private key | `AGE-SECRET-KEY-1...` |
| `FLUX_GITHUB_TOKEN` | GitHub PAT for Flux | `ghp_...` |

### Repository Setup

1. **Enable Actions**: Settings → Actions → Allow all actions
2. **Add Self-Hosted Runner**: Settings → Actions → Runners → New runner
3. **Configure Secrets**: As listed above

## 📖 Detailed Documentation

- **[Implementation Guide](./CI_CD_PIPELINE_IMPLEMENTATION.md)** - Complete file contents and examples
- **[Cluster Provisioning](./CLUSTER_PROVISIONING.md)** - Manual provisioning steps (for reference)
- **[RouterOS BGP Setup](./ROS_BGP_CHANGES_NEEDED.md)** - Manual RouterOS configuration (legacy)

## 🔄 Workflow Details

### terraform-plan.yml

**Triggers**: Pull Request modifying `terraform/**`

**Steps**:
1. Checkout code
2. Setup SOPS Age key
3. Install Terraform & Terragrunt
4. Run `terragrunt plan`
5. Comment plan output on PR

**Benefits**:
- Catch errors before merge
- Visibility into infrastructure changes
- Safe change review process

### cluster-provision-debian.yml

**Triggers**:
- Manual dispatch (workflow_dispatch)
- Push to `main` modifying `terraform/live/clusters/**` (optional)

**Inputs**:
- `cluster_id`: Which cluster (101, 102, etc.)
- `action`: plan or apply
- `skip_flux`: Skip Flux installation
- `skip_verify`: Skip health checks

**Steps**:
1. **Terraform Apply**: Provision VMs via Terragrunt
2. **Wait for VMs**: Check SSH and cloud-init completion
3. **Configure RouterOS**: Setup BGP peers and routes
4. **Bootstrap Kubernetes**: Run Ansible playbook
5. **Install Flux**: Bootstrap Flux CD from GitHub
6. **Verify Health**: Run health checks

**Duration**: ~15-20 minutes for full cluster

### cluster-destroy.yml

**Triggers**: Manual dispatch only

**Safety Features**:
- Requires manual confirmation input
- Drains workloads first
- Removes BGP routes before destroying VMs
- Cleanup verification

## 🧪 Testing Strategy

### Phase 1: Local Testing

```bash
# Test orchestration script locally
./.github/scripts/provision-cluster-debian.sh 101 plan --dry-run

# Test individual helpers
./.github/scripts/wait-for-vms.sh 101
./.github/scripts/verify-cluster-health.sh 101
```

### Phase 2: Workflow Testing

```bash
# Enable dry-run mode in workflow
# Test on cluster-102 (new cluster)
# Monitor logs carefully
```

### Phase 3: Production Rollout

```bash
# Use on cluster-103+ for new clusters
# Gradually migrate existing clusters
# Keep manual process as backup
```

## 🎛️ Configuration

### Customize Cluster Settings

Edit `terraform/live/clusters/cluster-XXX/cluster.hcl`:

```hcl
cluster_name = "sol"
cluster_id   = 101

control_plane = {
  instance_count = 3
  cpu_count      = 2
  memory_mb      = 8192
  disk_size_gb   = 20
}

workers = {
  instance_count = 3
  cpu_count      = 2
  memory_mb      = 16384
  disk_size_gb   = 100
}
```

### Customize Workflow Behavior

Edit `.github/workflows/cluster-provision-debian.yml`:

```yaml
# Change timeout
timeout-minutes: 60

# Add more cluster IDs
inputs:
  cluster_id:
    options:
      - '101'
      - '102'
      - '103'  # Add new clusters here
```

## 🐛 Troubleshooting

### Workflow fails at Terraform step

**Symptoms**: Error during `terragrunt apply`

**Checks**:
- ✅ SOPS Age key correct in GitHub Secrets
- ✅ Runner has network access to Proxmox
- ✅ Proxmox credentials valid in `terraform/live/common/secrets.sops.yaml`

**Debug**:
```bash
# Test locally
cd terraform/live/clusters/cluster-101
terragrunt plan
```

### VMs don't become ready

**Symptoms**: Timeout in "Wait for VMs" step

**Checks**:
- ✅ VMs are powered on in Proxmox
- ✅ Cloud-init completed: `ssh root@VM_IP cloud-init status`
- ✅ Network connectivity from runner to VMs

**Debug**:
```bash
# Check cloud-init logs
ssh root@<VM_IP> journalctl -u cloud-init

# Check Proxmox console
# PVE → VM → Console
```

### BGP sessions not established

**Symptoms**: Health check fails on BGP verification

**Checks**:
- ✅ FRR running: `ssh root@VM_IP systemctl status frr`
- ✅ BGP config correct: `ssh root@VM_IP vtysh -c 'show run'`
- ✅ RouterOS peers configured
- ✅ Firewall allows BGP (TCP 179)

**Debug**:
```bash
# Check FRR status
ssh root@<VM_IP> vtysh -c 'show bgp summary'

# Check RouterOS
ssh admin@routeros.local
/routing/bgp/connection print
/routing/bgp/session print
```

### Flux bootstrap fails

**Symptoms**: Error during Flux installation

**Checks**:
- ✅ GitHub token valid and has repo permissions
- ✅ Repository path exists: `kubernetes/clusters/production`
- ✅ SOPS Age key in correct location on nodes

**Debug**:
```bash
# Test Flux manually
flux check --pre
flux bootstrap github --help
```

## 📊 Monitoring

### GitHub Actions Dashboard

Monitor workflow runs:
- **Actions Tab**: See all workflow runs
- **Status Badges**: Add to README
- **Notifications**: Configure in Settings → Notifications

### Workflow Status in README

Add this badge to your README.md:

```markdown
![Cluster Provision](https://github.com/YOUR_USERNAME/home-ops/workflows/Provision%20Cluster%20(Debian)/badge.svg)
```

### Slack/Discord Notifications (Future)

Configure webhook notifications for:
- Workflow started
- Workflow succeeded
- Workflow failed

## 🔮 Future Enhancements

### Planned Features

1. **Talos Support** - Full Talos Linux pipeline
2. **Multi-Cluster** - Provision multiple clusters in parallel
3. **Blue/Green Deployments** - Zero-downtime cluster upgrades
4. **Automated Testing** - Smoke tests after provisioning
5. **Cost Tracking** - Resource usage metrics per cluster
6. **Monitoring Integration** - Prometheus metrics for provisioning

### Community Contributions

Want to contribute? Areas for improvement:

- Better error handling in scripts
- More comprehensive health checks
- Support for other virtualization platforms
- Windows runner support
- Integration with ArgoCD

## 📚 References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Terragrunt](https://terragrunt.gruntwork.io/)
- [Flux CD](https://fluxcd.io/)
- [SOPS](https://github.com/getsops/sops)

## 🆘 Support

For issues or questions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review workflow logs in GitHub Actions
3. Test components locally before filing issue
4. Provide full error logs and context

## 📝 License

This automation is part of the home-ops repository.

---

**Status**: 🚧 Work in Progress

**Last Updated**: 2025-01-10

**Maintainer**: @sulibot
