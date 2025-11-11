#!/usr/bin/env bash
#
# Debian Cluster Provisioning Orchestrator
#
# This script orchestrates the entire cluster provisioning workflow:
# 1. Terraform/Terragrunt apply (Proxmox VMs)
# 2. Wait for VMs to be ready
# 3. Configure RouterOS (BGP peers, static routes)
# 4. Bootstrap Kubernetes (via Ansible/kubeadm)
# 5. Install Flux CD
# 6. Verify cluster health
#
# Usage:
#   ./provision-cluster-debian.sh <cluster_id> [action] [options]
#
# Examples:
#   ./provision-cluster-debian.sh 101 apply
#   ./provision-cluster-debian.sh 102 plan
#   ./provision-cluster-debian.sh 101 apply --skip-flux
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
  --dry-run        Show what would be done without executing
  --help           Show this help message

Environment Variables:
  SOPS_AGE_KEY_FILE   Path to SOPS Age key (default: ~/.config/sops/age/age.agekey)
  ANSIBLE_INVENTORY   Path to Ansible inventory (default: ansible/k8s/inventory/hosts.ini)

Examples:
  $0 101 plan                    # Plan cluster-101 changes
  $0 102 apply                   # Provision cluster-102
  $0 101 apply --skip-flux       # Provision without Flux
  $0 101 destroy                 # Destroy cluster-101

EOF
    exit 0
}

# Parse arguments
CLUSTER_ID="${1:-}"
ACTION="${2:-plan}"
SKIP_FLUX=false
SKIP_VERIFY=false
DRY_RUN=false

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
ANSIBLE_DIR="${REPO_ROOT}/ansible/k8s"
SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-${HOME}/.config/sops/age/age.agekey}"
ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-${ANSIBLE_DIR}/inventory/hosts.ini}"

# Validate paths
if [[ ! -d "$CLUSTER_DIR" ]]; then
    log_error "Cluster directory not found: $CLUSTER_DIR"
    exit 1
fi

if [[ ! -f "$SOPS_AGE_KEY_FILE" ]]; then
    log_warn "SOPS Age key not found: $SOPS_AGE_KEY_FILE"
    log_warn "Secret decryption may fail"
fi

log_info "========================================="
log_info "  Debian Cluster Provisioning"
log_info "========================================="
log_info "Cluster ID:       cluster-${CLUSTER_ID}"
log_info "Action:           ${ACTION}"
log_info "Cluster Dir:      ${CLUSTER_DIR}"
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
        log_info "3. Configure RouterOS BGP/routes"
        log_info "4. Bootstrap Kubernetes via Ansible"
        [[ "$SKIP_FLUX" == "false" ]] && log_info "5. Install Flux CD"
        [[ "$SKIP_VERIFY" == "false" ]] && log_info "6. Verify cluster health"
    fi
    exit 0
fi

#
# Step 1: Terraform/Terragrunt
#
log_info ""
log_info "Step 1: Running Terraform ${ACTION}..."
cd "$CLUSTER_DIR"

if ! command -v terragrunt &> /dev/null; then
    log_error "terragrunt not found in PATH"
    exit 1
fi

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
        log_info "Running: terragrunt destroy -auto-approve"
        terragrunt destroy -auto-approve
        log_success "Cluster destroyed"
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
# Step 3: Configure RouterOS
#
log_info ""
log_info "Step 3: Configuring RouterOS (BGP, routes)..."
if [[ -x "${SCRIPT_DIR}/configure-routeros.sh" ]]; then
    "${SCRIPT_DIR}/configure-routeros.sh" "$CLUSTER_ID"
    log_success "RouterOS configured"
else
    log_warn "configure-routeros.sh not found"
    log_warn "Manual RouterOS configuration may be required"
    log_warn "See: docs/ROS_BGP_CHANGES_NEEDED.md"
fi

#
# Step 4: Bootstrap Kubernetes
#
log_info ""
log_info "Step 4: Bootstrapping Kubernetes..."
cd "$ANSIBLE_DIR"

if [[ ! -f "$ANSIBLE_INVENTORY" ]]; then
    log_error "Ansible inventory not found: $ANSIBLE_INVENTORY"
    exit 1
fi

# Check if bootstrap playbook exists
if [[ -f "playbooks/bootstrap-kubernetes.yml" ]]; then
    log_info "Running: ansible-playbook playbooks/bootstrap-kubernetes.yml"
    ansible-playbook -i "$ANSIBLE_INVENTORY" playbooks/bootstrap-kubernetes.yml
    log_success "Kubernetes bootstrapped"
else
    log_warn "Bootstrap playbook not found: playbooks/bootstrap-kubernetes.yml"
    log_warn "Manual Kubernetes initialization required"
    log_warn "See: ansible/k8s/README.md"
fi

#
# Step 5: Install Flux CD
#
if [[ "$SKIP_FLUX" == "false" ]]; then
    log_info ""
    log_info "Step 5: Installing Flux CD..."

    if [[ -f "playbooks/install-flux.yaml" ]]; then
        log_info "Running: ansible-playbook playbooks/install-flux.yaml"
        ansible-playbook -i "$ANSIBLE_INVENTORY" playbooks/install-flux.yaml
        log_success "Flux CD installed"
    else
        log_error "Flux playbook not found: playbooks/install-flux.yaml"
        exit 1
    fi
else
    log_info ""
    log_info "Step 5: Skipping Flux CD installation (--skip-flux)"
fi

#
# Step 6: Verify Cluster Health
#
if [[ "$SKIP_VERIFY" == "false" ]]; then
    log_info ""
    log_info "Step 6: Verifying cluster health..."

    if [[ -x "${SCRIPT_DIR}/verify-cluster-health.sh" ]]; then
        "${SCRIPT_DIR}/verify-cluster-health.sh" "$CLUSTER_ID"
        log_success "Cluster health verification passed"
    else
        log_warn "verify-cluster-health.sh not found"
        log_warn "Manual verification recommended"
    fi
else
    log_info ""
    log_info "Step 6: Skipping health verification (--skip-verify)"
fi

#
# Summary
#
log_info ""
log_success "========================================="
log_success "  Cluster Provisioning Complete!"
log_success "========================================="
log_info "Cluster:          cluster-${CLUSTER_ID}"
log_info "Next steps:"
log_info "  1. Verify nodes:     kubectl get nodes"
log_info "  2. Check Flux:       flux get all"
log_info "  3. Monitor apps:     kubectl get helmreleases -A"
log_success "========================================="
