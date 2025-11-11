#!/usr/bin/env bash
#
# Wait for VMs to be Ready
#
# This script waits for Proxmox VMs to become accessible via SSH
# and verifies that Talos is responding on the apid port.
#
# Usage:
#   ./wait-for-vms.sh <cluster_id>
#
# Example:
#   ./wait-for-vms.sh 101
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Validate arguments
CLUSTER_ID="${1:-}"
if [[ -z "$CLUSTER_ID" ]]; then
    log_error "Cluster ID is required"
    echo "Usage: $0 <cluster_id>"
    exit 1
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLUSTER_DIR="${REPO_ROOT}/terraform/live/clusters/cluster-${CLUSTER_ID}"
TIMEOUT=600  # 10 minutes
CHECK_INTERVAL=10

log_info "========================================="
log_info "  Waiting for VMs to be Ready"
log_info "========================================="
log_info "Cluster ID:  cluster-${CLUSTER_ID}"
log_info "Timeout:     ${TIMEOUT}s"
log_info "========================================="

# Get VM IPs from Terraform output
log_info "Retrieving VM IPs from Terraform..."
cd "$CLUSTER_DIR"

if ! terragrunt output -json &>/dev/null; then
    log_error "Failed to get Terraform outputs"
    log_error "Ensure Terraform has been applied successfully"
    exit 1
fi

CONTROL_PLANE_IPS=$(terragrunt output -json | jq -r '.control_plane_ips.value[]' 2>/dev/null || echo "")
WORKER_IPS=$(terragrunt output -json | jq -r '.worker_ips.value[]' 2>/dev/null || echo "")

if [[ -z "$CONTROL_PLANE_IPS" ]]; then
    log_error "No control plane IPs found in Terraform output"
    exit 1
fi

log_info "Control Plane IPs: $CONTROL_PLANE_IPS"
log_info "Worker IPs: ${WORKER_IPS:-none}"

ALL_IPS="$CONTROL_PLANE_IPS $WORKER_IPS"

# Function to check if Talos API is responding
check_talos_api() {
    local ip=$1
    # Try to connect to Talos apid port (50000)
    if timeout 5 bash -c "echo > /dev/tcp/$ip/50000" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to wait for a single VM
wait_for_vm() {
    local ip=$1
    local elapsed=0

    log_info "Waiting for VM $ip to be ready..."

    while (( elapsed < TIMEOUT )); do
        # Check if Talos API is responding
        if check_talos_api "$ip"; then
            log_success "VM $ip is ready (Talos API responding)"
            return 0
        fi

        sleep $CHECK_INTERVAL
        elapsed=$((elapsed + CHECK_INTERVAL))

        if (( elapsed % 30 == 0 )); then
            log_info "Still waiting for $ip... (${elapsed}s elapsed)"
        fi
    done

    log_error "Timeout waiting for VM $ip"
    return 1
}

# Wait for all VMs
log_info ""
log_info "Checking VM readiness..."
FAILED_VMS=()

for ip in $ALL_IPS; do
    if ! wait_for_vm "$ip"; then
        FAILED_VMS+=("$ip")
    fi
done

# Report results
log_info ""
log_info "========================================="
if [ ${#FAILED_VMS[@]} -eq 0 ]; then
    log_success "All VMs are ready!"
    log_success "========================================="
    exit 0
else
    log_error "Failed VMs: ${FAILED_VMS[*]}"
    log_error "========================================="
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "1. Check VM status in Proxmox UI"
    log_error "2. Verify VMs have booted (check console)"
    log_error "3. Check Talos NoCloud image is configured correctly"
    log_error "4. Verify network connectivity to VMs"
    log_error "5. Check Proxmox logs: pvesh get /nodes/<node>/tasks"
    exit 1
fi
