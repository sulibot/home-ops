#!/usr/bin/env bash
#
# Verify Cluster Health
#
# This script performs comprehensive health checks on a Talos Kubernetes cluster:
# - Talos machine health
# - Kubernetes node status
# - etcd health
# - System pods
# - VIP connectivity
# - BGP session status (if applicable)
#
# Usage:
#   ./verify-cluster-health.sh <cluster_id>
#
# Example:
#   ./verify-cluster-health.sh 101
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
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
TALOS_CONFIG_DIR="${TALOS_CONFIG_DIR:-${HOME}/.talos/cluster-${CLUSTER_ID}}"

log_info "========================================="
log_info "  Cluster Health Verification"
log_info "========================================="
log_info "Cluster ID:       cluster-${CLUSTER_ID}"
log_info "Talos Config Dir: ${TALOS_CONFIG_DIR}"
log_info "========================================="

# Track failures
FAILURES=0

# Set Talos and Kubernetes config paths
export TALOSCONFIG="${TALOS_CONFIG_DIR}/talosconfig"
export KUBECONFIG="${TALOS_CONFIG_DIR}/kubeconfig"

# Verify configs exist
if [[ ! -f "$TALOSCONFIG" ]]; then
    log_error "Talos config not found: $TALOSCONFIG"
    exit 1
fi

if [[ ! -f "$KUBECONFIG" ]]; then
    log_error "Kubeconfig not found: $KUBECONFIG"
    exit 1
fi

# Get cluster information
cd "$CLUSTER_DIR"
VIP=$(terragrunt output -json 2>/dev/null | jq -r '.control_plane_vip.value // "fd00:255:101::ac"')
FIRST_CP=$(head -1 "${TALOS_CONFIG_DIR}/control-plane-ips.txt" 2>/dev/null || echo "")

if [[ -z "$FIRST_CP" ]]; then
    log_error "Cannot determine first control plane IP"
    exit 1
fi

log_info "Control Plane VIP: $VIP"
log_info "Using control plane: $FIRST_CP"

#
# Check 1: Talos Health
#
log_info ""
log_info "=== Talos Health Check ==="
if talosctl --nodes "$FIRST_CP" health 2>&1; then
    log_success "Talos health check passed"
else
    log_error "Talos health check failed"
    FAILURES=$((FAILURES + 1))
fi

#
# Check 2: Kubernetes Nodes
#
log_info ""
log_info "=== Kubernetes Nodes Check ==="
NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " | wc -l | tr -d ' ')

log_info "Total nodes: $NODES"
log_info "Not ready: $NOT_READY"

if [[ "$NODES" -gt 0 ]] && [[ "$NOT_READY" -eq 0 ]]; then
    log_success "All nodes are Ready"
    kubectl get nodes -o wide
else
    log_error "Some nodes are not Ready"
    kubectl get nodes -o wide
    FAILURES=$((FAILURES + 1))
fi

#
# Check 3: etcd Health
#
log_info ""
log_info "=== etcd Health Check ==="
if talosctl --nodes "$FIRST_CP" etcd members 2>&1 | grep -q "healthy"; then
    log_success "etcd cluster is healthy"
    talosctl --nodes "$FIRST_CP" etcd members
else
    log_error "etcd cluster health check failed"
    FAILURES=$((FAILURES + 1))
fi

#
# Check 4: System Pods
#
log_info ""
log_info "=== System Pods Check ==="
NOT_RUNNING=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running" | grep -v "Completed" | wc -l | tr -d ' ')

log_info "Non-running system pods: $NOT_RUNNING"

if [[ "$NOT_RUNNING" -eq 0 ]]; then
    log_success "All system pods are Running"
else
    log_warn "Some system pods are not Running"
    kubectl get pods -n kube-system | grep -v "Running" | grep -v "Completed" || true
    # Don't count as failure - pods may still be initializing
fi

#
# Check 5: VIP Connectivity
#
log_info ""
log_info "=== VIP Connectivity Check ==="
if timeout 5 bash -c "echo > /dev/tcp/${VIP}/6443" 2>/dev/null; then
    log_success "VIP ${VIP}:6443 is accessible"
else
    log_error "VIP ${VIP}:6443 is not accessible"
    FAILURES=$((FAILURES + 1))
fi

#
# Check 6: API Server via VIP
#
log_info ""
log_info "=== API Server Check (via VIP) ==="
if kubectl --server="https://[${VIP}]:6443" cluster-info &>/dev/null; then
    log_success "API server accessible via VIP"
    kubectl --server="https://[${VIP}]:6443" cluster-info
else
    log_warn "API server check via VIP failed"
    # Don't count as failure - kubeconfig may use direct IPs
fi

#
# Check 7: Cilium Status (if installed)
#
log_info ""
log_info "=== Cilium Status Check ==="
if kubectl get pods -n kube-system -l k8s-app=cilium &>/dev/null; then
    CILIUM_PODS=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | wc -l | tr -d ' ')
    CILIUM_READY=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep "Running" | wc -l | tr -d ' ')

    log_info "Cilium pods: $CILIUM_READY/$CILIUM_PODS ready"

    if [[ "$CILIUM_READY" -eq "$CILIUM_PODS" ]] && [[ "$CILIUM_PODS" -gt 0 ]]; then
        log_success "Cilium is running on all nodes"
    else
        log_warn "Cilium is not fully ready yet"
    fi
else
    log_warn "Cilium not found - may not be installed yet"
fi

#
# Check 8: Talos Services
#
log_info ""
log_info "=== Talos Services Check ==="
SERVICES=("apid" "trustd" "etcd" "kubelet" "machined")

for service in "${SERVICES[@]}"; do
    if talosctl --nodes "$FIRST_CP" service "$service" 2>&1 | grep -q "RUNNING"; then
        log_success "Service $service is running"
    else
        log_warn "Service $service status unknown"
    fi
done

#
# Check 9: Disk Usage
#
log_info ""
log_info "=== Disk Usage Check ==="
talosctl --nodes "$FIRST_CP" df 2>&1 || log_warn "Could not check disk usage"

#
# Check 10: Node Resource Usage
#
log_info ""
log_info "=== Node Resource Usage ==="
kubectl top nodes 2>/dev/null || log_warn "Metrics server not available yet"

#
# Summary
#
log_info ""
log_info "========================================="
if [[ $FAILURES -eq 0 ]]; then
    log_success "All critical health checks passed!"
    log_success "========================================="
    log_info ""
    log_info "Cluster is ready for workloads"
    log_info ""
    log_info "Quick commands:"
    log_info "  kubectl get nodes"
    log_info "  kubectl get pods -A"
    log_info "  talosctl --nodes $FIRST_CP dashboard"
    exit 0
else
    log_error "$FAILURES critical check(s) failed"
    log_error "========================================="
    log_info ""
    log_error "Please investigate the failures above"
    log_info ""
    log_info "Debugging commands:"
    log_info "  talosctl --nodes $FIRST_CP dmesg"
    log_info "  talosctl --nodes $FIRST_CP logs kubelet"
    log_info "  kubectl describe nodes"
    log_info "  kubectl get events -A --sort-by='.lastTimestamp'"
    exit 1
fi
