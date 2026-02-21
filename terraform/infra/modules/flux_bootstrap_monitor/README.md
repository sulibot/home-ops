# Flux Bootstrap Monitor Module

Monitors Flux app bootstrap progress and automatically switches intervals from aggressive to steady-state when complete.

**More transparent than bash scripts** - uses Terraform data sources, outputs, and clear console formatting.

## What It Does

1. **Monitors Bootstrap Progress** (15-min timeout)
   - Checks Tier 0 (Foundation) Ready status
   - Checks Tier 1 (Infrastructure) Ready status
   - Checks 3 critical apps: plex, home-assistant, immich

2. **Visual Progress Tracking**
   - Clear console output with timestamps
   - Shows elapsed time during wait loops
   - Color-coded status boxes

3. **Auto-Switches Intervals** (optional)
   - Tier 0: 30s → 15m
   - Tier 1: 1m → 10m
   - Tier 2: 2m → 15m
   - Commits and pushes changes to Git
   - Flux auto-updates from Git

## Usage

### Option 1: Fully Automated (Recommended)

Run as part of cluster bootstrap:

```bash
cd terraform/infra/live/clusters/cluster-101/flux-bootstrap-monitor
terragrunt apply
```

With `auto_switch_intervals = true` (default), the module will:
1. Wait for bootstrap complete (max 15 min)
2. Automatically switch intervals
3. Commit and push to Git
4. Flux will pick up the new intervals

### Option 2: Manual Control

Set `auto_switch_intervals = false` in `terragrunt.hcl`:

```hcl
inputs = {
  auto_switch_intervals = false  # Don't auto-switch
}
```

Then manually trigger interval switch later:

```bash
# Check status first
terragrunt output

# When ready, switch intervals
cd /path/to/repo
sed -i 's/interval: 30s/interval: 15m/g' kubernetes/apps/tier-0-foundation/ks.yaml
sed -i 's/interval: 1m/interval: 10m/g' kubernetes/apps/tier-1-infrastructure/ks.yaml
sed -i 's/interval: 2m/interval: 15m/g' kubernetes/apps/tier-2-applications/ks.yaml
git commit -am "chore: switch to steady-state intervals"
git push
```

### Option 3: Check Status Only

To just check bootstrap status without waiting:

```bash
terragrunt plan  # Shows current status in plan output
terragrunt output  # Shows outputs after apply
```

## Outputs

```hcl
tier_0_ready          = "True"         # Tier 0 Ready status
tier_1_ready          = "True"         # Tier 1 Ready status
plex_ready            = "True"         # Plex Ready status
home_assistant_ready  = "True"         # Home Assistant Ready status
immich_ready          = "True"         # Immich Ready status
bootstrap_complete    = true           # Overall bootstrap status
intervals_switched    = true           # Whether intervals have been switched
```

## Dependencies

This module should run **AFTER** `flux-instance`:

```hcl
dependencies {
  paths = ["../flux-instance"]
}
```

## Timeout

The module will fail after **15 minutes** if bootstrap doesn't complete. This prevents indefinite hangs and surfaces issues early.

If you need more time, edit the timeout in `main.tf`:

```hcl
TIMEOUT_SECONDS=900  # Change to 1800 for 30 minutes
```

## Advantages Over Bash Script

| Bash Script | Terraform Module |
|-------------|------------------|
| Opaque execution | Clear Terraform outputs |
| Hard to debug | State tracked in Terraform |
| No status visibility | `terraform output` shows status |
| Manual integration | Native Terragrunt integration |
| Exit codes only | Rich outputs and state |

## Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 TIER 0 (Foundation) Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Ready: True

Apps included:
  • gateway-api-crds
  • snapshot-controller-crds
  • cilium (CNI)
  • external-secrets + onepassword
  • ceph-csi (storage)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏳ WAITING FOR BOOTSTRAP COMPLETE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Timeout: 15 minutes (900 seconds)

Checking Tier 0 (Foundation)...
  ✅ Tier 0 Ready

Checking Tier 1 (Infrastructure)...
  ⏳ [2m 30s] Tier 1 not ready, waiting...
  ⏳ [2m 40s] Tier 1 not ready, waiting...
  ✅ Tier 1 Ready

Checking Critical Apps...
  ✅ plex Ready
  ✅ home-assistant Ready
  ⏳ [5m 10s] Waiting for: immich
  ✅ immich Ready

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ BOOTSTRAP COMPLETE!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total time: 8m 45s
```

## Troubleshooting

### Bootstrap stuck/timeout

Check individual component status:

```bash
kubectl get kustomizations -A
kubectl get helmreleases -A
flux logs --level=error
```

### Intervals not switching

Check git status:

```bash
cd /path/to/repo
git status
git log -1  # Should show "switch to steady-state intervals" commit
```

### Data source errors

The Kubernetes resources might not exist yet. The module uses `try()` to handle this, but very early failures may occur. Ensure `flux-instance` completed successfully first.
