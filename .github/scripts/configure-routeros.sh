#!/usr/bin/env bash
#
# Configure RouterOS BGP and Routes
#
# This script configures RouterOS with BGP peers and static routes
# for a Kubernetes cluster using IPv6.
#
# Usage:
#   ./configure-routeros.sh <cluster_id>
#
# Example:
#   ./configure-routeros.sh 101
#
# Prerequisites:
#   - RouterOS API access configured
#   - ssh access to RouterOS device
#   - Environment variables for RouterOS credentials (optional)
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

# RouterOS configuration
ROUTEROS_HOST="${ROUTEROS_HOST:-fd00:0:0:ffff::fffe}"
ROUTEROS_USER="${ROUTEROS_USER:-admin}"
ROUTEROS_ASN="${ROUTEROS_ASN:-65000}"
CLUSTER_ASN="${CLUSTER_ASN:-65101}"

log_info "========================================="
log_info "  Configuring RouterOS for Cluster"
log_info "========================================="
log_info "Cluster ID:     cluster-${CLUSTER_ID}"
log_info "RouterOS Host:  ${ROUTEROS_HOST}"
log_info "RouterOS ASN:   ${ROUTEROS_ASN}"
log_info "Cluster ASN:    ${CLUSTER_ASN}"
log_info "========================================="

# Get VM IPs from Terraform
log_info "Retrieving cluster IPs from Terraform..."
cd "$CLUSTER_DIR"

if ! terragrunt output -json &>/dev/null; then
    log_error "Failed to get Terraform outputs"
    exit 1
fi

CONTROL_PLANE_IPS=$(terragrunt output -json | jq -r '.control_plane_ips.value[]' 2>/dev/null || echo "")
WORKER_IPS=$(terragrunt output -json | jq -r '.worker_ips.value[]' 2>/dev/null || echo "")
VIP=$(terragrunt output -json | jq -r '.control_plane_vip.value // "fd00:255:101::ac"')

if [[ -z "$CONTROL_PLANE_IPS" ]]; then
    log_error "No control plane IPs found"
    exit 1
fi

log_info "Control Plane VIP: $VIP"
log_info "Control Plane IPs: $CONTROL_PLANE_IPS"
log_info "Worker IPs: ${WORKER_IPS:-none}"

ALL_NODE_IPS="$CONTROL_PLANE_IPS $WORKER_IPS"

# Check SSH connectivity to RouterOS
log_info ""
log_info "Checking RouterOS connectivity..."
if ! ssh -o ConnectTimeout=5 "${ROUTEROS_USER}@${ROUTEROS_HOST}" /system resource print &>/dev/null; then
    log_error "Cannot connect to RouterOS via SSH"
    log_error "Please ensure:"
    log_error "  1. SSH service is enabled on RouterOS"
    log_error "  2. SSH keys are configured"
    log_error "  3. Network connectivity exists"
    exit 1
fi
log_success "RouterOS connection OK"

# Function to execute RouterOS commands
ros_cmd() {
    ssh "${ROUTEROS_USER}@${ROUTEROS_HOST}" "$@"
}

# Configure BGP instance (if not exists)
log_info ""
log_info "Configuring BGP instance..."
ros_cmd <<'EOF'
/routing/bgp/template
:if ([:len [find name="k8s-cluster"]] = 0) do={
    add name="k8s-cluster" as=65000 routing-table=main
    :log info "Created BGP template k8s-cluster"
} else={
    :log info "BGP template k8s-cluster already exists"
}
EOF
log_success "BGP instance configured"

# Configure BGP peers for all nodes
log_info ""
log_info "Configuring BGP peers..."

for NODE_IP in $ALL_NODE_IPS; do
    log_info "Adding BGP peer: $NODE_IP"
    ros_cmd <<EOF
/routing/bgp/connection
:if ([:len [find name="k8s-node-${NODE_IP}"]] = 0) do={
    add name="k8s-node-${NODE_IP}" \\
        template=k8s-cluster \\
        remote.address="${NODE_IP}" \\
        remote.as=${CLUSTER_ASN} \\
        listen=yes \\
        connect=yes \\
        hold-time=30s \\
        keepalive-time=10s \\
        address-families=ipv6,ipv4
    :log info "Created BGP peer k8s-node-${NODE_IP}"
} else={
    :log info "BGP peer k8s-node-${NODE_IP} already exists"
}
EOF
done

log_success "BGP peers configured"

# Add static route for cluster VIP (as backup)
log_info ""
log_info "Configuring static route for VIP..."
ros_cmd <<EOF
/ipv6/route
:if ([:len [find comment="cluster-${CLUSTER_ID}-vip"]] = 0) do={
    add dst-address="${VIP}/128" \\
        type=blackhole \\
        comment="cluster-${CLUSTER_ID}-vip" \\
        distance=200
    :log info "Created static route for ${VIP}"
} else={
    :log info "Static route for ${VIP} already exists"
}
EOF
log_success "Static route configured"

# Verify BGP sessions
log_info ""
log_info "Verifying BGP sessions..."
sleep 5  # Give BGP time to establish

BGP_STATUS=$(ros_cmd "/routing/bgp/session print detail where established")

if [[ -n "$BGP_STATUS" ]]; then
    log_success "BGP sessions established:"
    echo "$BGP_STATUS"
else
    log_warn "No established BGP sessions found yet"
    log_warn "This is normal if the cluster is still initializing"
    log_warn "BGP sessions will establish once FRR is running on nodes"
fi

# Display summary
log_info ""
log_info "========================================="
log_success "RouterOS Configuration Complete"
log_info "========================================="
log_info ""
log_info "Next steps:"
log_info "  1. Verify BGP sessions establish after cluster is up"
log_info "  2. Check routes are being advertised"
log_info "  3. Test VIP connectivity from RouterOS"
log_info ""
log_info "Manual verification commands:"
log_info "  ssh ${ROUTEROS_USER}@${ROUTEROS_HOST}"
log_info "  /routing/bgp/session print"
log_info "  /ipv6/route print where bgp"
log_info "========================================="
