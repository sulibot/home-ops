# Apply Talos Machine Configurations

This step applies Talos machine configurations to **running nodes** without bootstrapping the cluster.

## When to Use This

Use this step when you want to update machine configurations on an already-running cluster:

- ✅ Network configuration changes (adding/removing IP addresses)
- ✅ System extension changes
- ✅ Sysctls modifications
- ✅ Time server changes
- ✅ Kubelet configuration updates
- ✅ FRR/BGP configuration (inline manifests)
- ✅ Most machine config patches

## When NOT to Use This

Do NOT use this for:

- ❌ Initial cluster bootstrap (use `../bootstrap/` instead)
- ❌ Kubernetes version upgrades (use dedicated upgrade process)
- ❌ Changes that require VM recreation (use `../compute/`)

## Usage

### Step 1: Update Machine Configs

First, regenerate the machine configs with your changes:

```bash
cd ../config
terragrunt apply
```

### Step 2: Apply to Running Nodes

Apply the updated configs to all nodes:

```bash
cd ../apply
terragrunt apply
```

This will:
1. Read the latest machine configs from `../config/`
2. Apply them to all running nodes via `talosctl apply-config`
3. Nodes will apply changes live (most changes don't require reboot)

## What Gets Applied

The `talos_machine_configuration_apply` resource:
- Connects to each node via Talos API
- Applies the new machine configuration
- Talos merges the changes into the running configuration
- Most changes take effect immediately

## Comparison with Bootstrap

| Step | Bootstrap | Apply |
|------|-----------|-------|
| Purpose | Initial cluster creation | Update running cluster |
| When | Once, at cluster creation | Repeatedly, for updates |
| What it does | Bootstrap etcd + Apply configs + Install Flux | Only apply configs |
| Safe to rerun | No (will fail if cluster exists) | Yes (idempotent) |

## Typical Workflow

```bash
# 1. Make changes to Terraform config (e.g., add IP address)
vim ../../common/versions.hcl

# 2. Regenerate machine configs
cd ../config && terragrunt apply

# 3. Apply to running cluster
cd ../apply && terragrunt apply

# 4. Verify changes
talosctl -n 10.0.101.11 get addresses
```

## Dependencies

This step depends on:
- `../config/` - Must run first to generate machine configs
- Running cluster - Nodes must be accessible via Talos API

## Endpoints

The apply step connects to nodes via:
- **Primary**: IPv6 ULA addresses (e.g., `fd00:101::11`)
- **Fallback**: IPv4 addresses (e.g., `10.0.101.11`)

Make sure nodes are reachable before running this step.
