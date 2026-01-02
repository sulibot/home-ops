#!/usr/bin/env bash
#
# Talos Cluster Provisioning Orchestrator
#
# This script orchestrates the entire Talos cluster provisioning workflow:
# 1. Terraform/Terragrunt apply (Proxmox VMs with Talos NoCloud image)
# 2. Wait for VMs to be ready
# 3. Generate Talos machine configurations
# 4. Apply Talos configurations (talosctl apply-config)
# 5. Bootstrap Kubernetes (talosctl bootstrap)
# 6. Configure RouterOS (BGP peers, static routes)
# 7. Install Flux CD
# 8. Verify cluster health
#
# Usage:
#   ./provision-cluster-talos.sh <cluster_id> [action] [options]
#
# Examples:
#   ./provision-cluster-talos.sh 101 apply
#   ./provision-cluster-talos.sh 102 plan
#   ./provision-cluster-talos.sh 101 apply --skip-flux
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 <cluster_id> [action] [options]

Arguments:
  cluster_id       Cluster ID (e.g., 101, 102)
  action           Action to perform: plan|apply|destroy (default: plan)

Options:
  --skip-flux      Skip Flux CD installation
  --skip-verify    Skip post-provision health checks
  --talos-version  Talos version (default: v1.11.3)
  --dry-run        Show what would be done without executing
  --help           Show this help message

Environment Variables:
  SOPS_AGE_KEY_FILE       Path to SOPS Age key (default: ~/.config/sops/age/age.agekey)
  TALOS_CONFIG_DIR        Path to store Talos configs (default: ~/.talos)
  GITHUB_TOKEN            GitHub PAT for Flux bootstrap

Examples:
  $0 101 plan                        # Plan cluster-101 changes
  $0 102 apply                       # Provision cluster-102
  $0 101 apply --skip-flux           # Provision without Flux
  $0 101 apply --talos-version v1.12.0  # Use specific Talos version
  $0 101 destroy                     # Destroy cluster-101

EOF
    exit 0
}

# Parse arguments
CLUSTER_ID="${1:-}"
ACTION="${2:-plan}"
SKIP_FLUX=false
SKIP_VERIFY=false
DRY_RUN=false
TALOS_VERSION="v1.11.3"

# Shift past positional args
shift 2 2>/dev/null || true

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-flux)
            SKIP_FLUX=true
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        --talos-version)
            TALOS_VERSION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate cluster ID
if [[ -z "$CLUSTER_ID" ]]; then
    log_error "Cluster ID is required"
    usage
fi

if ! [[ "$CLUSTER_ID" =~ ^[0-9]+$ ]]; then
    log_error "Cluster ID must be numeric"
    exit 1
fi

# Validate action
if [[ ! "$ACTION" =~ ^(plan|apply|destroy)$ ]]; then
    log_error "Action must be one of: plan, apply, destroy"
    exit 1
fi

# Set paths
CLUSTER_DIR="${REPO_ROOT}/terraform/live/clusters/cluster-${CLUSTER_ID}"
TALOS_CONFIG_DIR="${TALOS_CONFIG_DIR:-${HOME}/.talos/cluster-${CLUSTER_ID}}"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-${HOME}/.config/sops/age/age.agekey}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Validate paths
if [[ ! -d "$CLUSTER_DIR" ]]; then
    log_error "Cluster directory not found: $CLUSTER_DIR"
    exit 1
fi

if [[ ! -f "$SOPS_AGE_KEY_FILE" ]]; then
    log_warn "SOPS Age key not found: $SOPS_AGE_KEY_FILE"
    log_warn "Secret decryption may fail"
fi

# Check for required tools
for tool in terraform terragrunt talosctl kubectl flux; do
    if ! command -v "$tool" &> /dev/null; then
        log_error "$tool not found in PATH"
        exit 1
    fi
done

log_info "========================================="
log_info "  Talos Cluster Provisioning"
log_info "========================================="
log_info "Cluster ID:       cluster-${CLUSTER_ID}"
log_info "Action:           ${ACTION}"
log_info "Talos Version:    ${TALOS_VERSION}"
log_info "Cluster Dir:      ${CLUSTER_DIR}"
log_info "Talos Config Dir: ${TALOS_CONFIG_DIR}"
log_info "Skip Flux:        ${SKIP_FLUX}"
log_info "Skip Verify:      ${SKIP_VERIFY}"
log_info "Dry Run:          ${DRY_RUN}"
log_info "========================================="

# Dry run check
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN MODE - No changes will be made"
    log_info ""
    log_info "Would execute:"
    log_info "1. Terraform ${ACTION} in ${CLUSTER_DIR}"
    if [[ "$ACTION" == "apply" ]]; then
        log_info "2. Wait for VMs to be ready"
        log_info "3. Generate Talos machine configs"
        log_info "4. Apply Talos configs (talosctl apply-config)"
        log_info "5. Bootstrap Kubernetes (talosctl bootstrap)"
        log_info "6. Configure RouterOS BGP/routes"
        [[ "$SKIP_FLUX" == "false" ]] && log_info "7. Install Flux CD"
        [[ "$SKIP_VERIFY" == "false" ]] && log_info "8. Verify cluster health"
    fi
    exit 0
fi

#
# Step 1: Terraform/Terragrunt
#
log_info ""
log_info "Step 1: Running Terraform ${ACTION}..."
cd "$CLUSTER_DIR"

case "$ACTION" in
    plan)
        log_info "Running: terragrunt plan"
        terragrunt plan
        log_success "Terraform plan completed"
        exit 0
        ;;
    apply)
        log_info "Running: terragrunt apply -auto-approve"
        terragrunt apply -auto-approve
        log_success "Terraform apply completed"
        ;;
    destroy)
        log_warn "Destroying cluster-${CLUSTER_ID}..."
        log_warn "This will delete all VMs and resources!"
        read -p "Are you sure? Type 'yes' to confirm: " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Destroy cancelled"
            exit 0
        fi

        # Drain cluster first if it exists
        if talosctl --talosconfig "${TALOS_CONFIG_DIR}/talosconfig" \
            --nodes "$(cat ${TALOS_CONFIG_DIR}/control-plane-ips.txt 2>/dev/null | head -1)" \
            version &>/dev/null; then
            log_info "Draining cluster before destruction..."
            kubectl drain --all --ignore-daemonsets --delete-emptydir-data --force || true
        fi

        log_info "Running: terragrunt destroy -auto-approve"
        terragrunt destroy -auto-approve
        log_success "Cluster destroyed"

        # Cleanup Talos configs
        log_info "Cleaning up Talos configurations..."
        rm -rf "$TALOS_CONFIG_DIR"
        log_success "Cleanup complete"
        exit 0
        ;;
esac

#
# Step 2: Wait for VMs
#
log_info ""
log_info "Step 2: Waiting for VMs to be ready..."
if [[ -x "${SCRIPT_DIR}/wait-for-vms.sh" ]]; then
    "${SCRIPT_DIR}/wait-for-vms.sh" "$CLUSTER_ID"
else
    log_warn "wait-for-vms.sh not found or not executable, sleeping for 60s..."
    sleep 60
fi
log_success "VMs are ready"

#
# Step 3: Generate Talos Machine Configurations
#
log_info ""
log_info "Step 3: Generating Talos machine configurations..."

# Create Talos config directory
mkdir -p "$TALOS_CONFIG_DIR"

# Get VM IPs from Terraform output
log_info "Extracting VM IPs from Terraform output..."
cd "$CLUSTER_DIR"
CONTROL_PLANE_IPS=$(terragrunt output -json | jq -r '.control_plane_ips.value[]' | tr '\n' ' ')
WORKER_IPS=$(terragrunt output -json | jq -r '.worker_ips.value[]' | tr '\n' ' ')
VIP=$(terragrunt output -json | jq -r '.control_plane_vip.value // "fd00:255:101::ac"')

# Save IPs for later use
echo "$CONTROL_PLANE_IPS" | tr ' ' '\n' > "${TALOS_CONFIG_DIR}/control-plane-ips.txt"
echo "$WORKER_IPS" | tr ' ' '\n' > "${TALOS_CONFIG_DIR}/worker-ips.txt"

FIRST_CP=$(echo "$CONTROL_PLANE_IPS" | awk '{print $1}')

log_info "Control Plane VIP: $VIP"
log_info "Control Plane IPs: $CONTROL_PLANE_IPS"
log_info "Worker IPs: $WORKER_IPS"

# Generate secrets
log_info "Generating Talos secrets..."
talosctl gen secrets \
    --output-file "${TALOS_CONFIG_DIR}/secrets.yaml"

# Generate machine configs
log_info "Generating Talos machine configs..."
talosctl gen config \
    "cluster-${CLUSTER_ID}" \
    "https://[${VIP}]:6443" \
    --with-secrets "${TALOS_CONFIG_DIR}/secrets.yaml" \
    --config-patch @<(cat <<EOF
machine:
  kubelet:
    nodeIP:
      validSubnets:
        - fd00:101::/64
        - 10.244.0.0/16
  network:
    interfaces:
      - interface: eth0
        dhcp: false
        addresses:
          - REPLACE_WITH_NODE_IP
        routes:
          - network: ::/0
            gateway: fd00:101::1
      - interface: eth1
        dhcp: false
        addresses:
          - REPLACE_WITH_EGRESS_IP
        routes:
          - network: 0.0.0.0/0
            gateway: fd00:0:0:ffff::1
cluster:
  network:
    cni:
      name: none  # We'll use Cilium via Flux
    podSubnets:
      - fd00:101:44::/60
      - 10.244.0.0/16
    serviceSubnets:
      - fd00:101:96::/108
      - 10.96.0.0/12
  proxy:
    disabled: true  # Using Cilium kube-proxy replacement
EOF
    ) \
    --output "${TALOS_CONFIG_DIR}" \
    --output-types controlplane,worker,talosconfig

log_success "Talos configs generated"

#
# Step 4: Apply Talos Configurations
#
log_info ""
log_info "Step 4: Applying Talos configurations..."

# Configure talosctl
export TALOSCONFIG="${TALOS_CONFIG_DIR}/talosconfig"

# Apply control plane configs
log_info "Applying control plane configurations..."
for ip in $CONTROL_PLANE_IPS; do
    log_info "Preparing and applying config to control plane: $ip"

    # Create a node-specific config from the template
    NODE_CONFIG_FILE="${TALOS_CONFIG_DIR}/controlplane-${ip}.yaml"
    cp "${TALOS_CONFIG_DIR}/controlplane.yaml" "$NODE_CONFIG_FILE"

    # Inject the node's static IP into the machine config to make it permanent.
    # This IP must match the one injected by Cloud-Init.
    log_info "Injecting permanent static IP $ip into $NODE_CONFIG_FILE"
    # Note: This assumes your generated config has placeholders like REPLACE_WITH_NODE_IP.
    # The IPv6 address is assumed to be the primary for the first interface.
    sed -i "s|REPLACE_WITH_NODE_IP|${ip}/64|g" "$NODE_CONFIG_FILE"
    # TODO: Add sed replacement for the second (egress) NIC if needed.

    talosctl apply-config \
        --insecure \
        --nodes "$ip" \
        --file "$NODE_CONFIG_FILE" \
        || log_warn "Failed to apply config to $ip (may need a retry)"
done

# Wait for control planes to be ready
log_info "Waiting for control planes to be ready..."
sleep 30

# Apply worker configs
if [[ -n "$WORKER_IPS" ]]; then
    log_info "Applying worker configurations..."
    for ip in $WORKER_IPS; do
        log_info "Preparing and applying config to worker: $ip"

        NODE_CONFIG_FILE="${TALOS_CONFIG_DIR}/worker-${ip}.yaml"
        cp "${TALOS_CONFIG_DIR}/worker.yaml" "$NODE_CONFIG_FILE"

        log_info "Injecting permanent static IP $ip into $NODE_CONFIG_FILE"
        sed -i "s|REPLACE_WITH_NODE_IP|${ip}/64|g" "$NODE_CONFIG_FILE"

        talosctl apply-config \
            --insecure \
            --nodes "$ip" \
            --file "$NODE_CONFIG_FILE" \
            || log_warn "Failed to apply config to $ip (may need a retry)"
    done
fi

log_success "Talos configurations applied"

#
# Step 5: Bootstrap Kubernetes
#
log_info ""
log_info "Step 5: Bootstrapping Kubernetes..."

log_info "Bootstrapping on first control plane: $FIRST_CP"
talosctl bootstrap \
    --nodes "$FIRST_CP" \
    --endpoints "$FIRST_CP"

log_info "Waiting for Kubernetes API to be available..."
timeout=300
elapsed=0
while (( elapsed < timeout )); do
    if talosctl --nodes "$FIRST_CP" kubeconfig "${TALOS_CONFIG_DIR}/kubeconfig" 2>/dev/null; then
        log_success "Kubernetes API is available"
        break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    if (( elapsed >= timeout )); then
        log_error "Timeout waiting for Kubernetes API"
        exit 1
    fi
done

# Merge kubeconfig
log_info "Merging kubeconfig..."
export KUBECONFIG="${TALOS_CONFIG_DIR}/kubeconfig"
kubectl config view --flatten > ~/.kube/config-cluster-${CLUSTER_ID}
KUBECONFIG=~/.kube/config:~/.kube/config-cluster-${CLUSTER_ID} \
    kubectl config view --flatten > ~/.kube/config-merged
mv ~/.kube/config-merged ~/.kube/config

log_success "Kubernetes bootstrapped"

#
# Step 6: Configure RouterOS
#
log_info ""
log_info "Step 6: Configuring RouterOS (BGP, routes)..."
if [[ -x "${SCRIPT_DIR}/configure-routeros.sh" ]]; then
    "${SCRIPT_DIR}/configure-routeros.sh" "$CLUSTER_ID"
    log_success "RouterOS configured"
else
    log_warn "configure-routeros.sh not found"
    log_warn "Manual RouterOS configuration may be required"
    log_warn "See: docs/ROS_BGP_CHANGES_NEEDED.md"
fi

#
# Step 7: Install Flux CD
#
if [[ "$SKIP_FLUX" == "false" ]]; then
    log_info ""
    log_info "Step 7: Installing Flux CD..."

    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_error "GITHUB_TOKEN environment variable not set"
        log_error "Set it and run: flux bootstrap github ..."
        exit 1
    fi

    # Create SOPS secret for Flux
    log_info "Creating SOPS Age secret..."
    kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic sops-age \
        --namespace=flux-system \
        --from-file=age.agekey="$SOPS_AGE_KEY_FILE" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Bootstrap Flux
    log_info "Bootstrapping Flux from GitHub..."
    flux bootstrap github \
        --owner="$(git config --get remote.origin.url | sed -E 's|.*github.com[:/]([^/]+)/.*|\1|')" \
        --repository="$(git config --get remote.origin.url | sed -E 's|.*github.com[:/][^/]+/([^.]+).*|\1|')" \
        --branch=main \
        --path=kubernetes/clusters/production \
        --personal \
        --private \
        --token-auth

    log_success "Flux CD installed"
else
    log_info ""
    log_info "Step 7: Skipping Flux CD installation (--skip-flux)"
fi

#
# Step 8: Verify Cluster Health
#
if [[ "$SKIP_VERIFY" == "false" ]]; then
    log_info ""
    log_info "Step 8: Verifying cluster health..."

    if [[ -x "${SCRIPT_DIR}/verify-cluster-health.sh" ]]; then
        "${SCRIPT_DIR}/verify-cluster-health.sh" "$CLUSTER_ID"
        log_success "Cluster health verification passed"
    else
        log_warn "verify-cluster-health.sh not found"
        log_warn "Manual verification recommended"
    fi
else
    log_info ""
    log_info "Step 8: Skipping health verification (--skip-verify)"
fi

#
# Summary
#
log_info ""
log_success "========================================="
log_success "  Talos Cluster Provisioning Complete!"
log_success "========================================="
log_info "Cluster:          cluster-${CLUSTER_ID}"
log_info "Talos Version:    ${TALOS_VERSION}"
log_info "Talos Config:     ${TALOS_CONFIG_DIR}"
log_info "Kubeconfig:       ~/.kube/config (merged)"
log_info ""
log_info "Next steps:"
log_info "  1. Verify nodes:     kubectl get nodes"
log_info "  2. Check Talos:      talosctl --nodes $FIRST_CP health"
log_info "  3. Check Flux:       flux get all"
log_info "  4. Monitor apps:     kubectl get helmreleases -A"
log_info ""
log_info "Talosctl usage:"
log_info "  export TALOSCONFIG=${TALOS_CONFIG_DIR}/talosconfig"
log_info "  talosctl --nodes $FIRST_CP dashboard"
log_success "========================================="
