#!/usr/bin/env bash
#
# Configure RouterOS BGP and Routes for PVE Fabric
#
# This script configures RouterOS with BGP peers matching the FRR
# configuration on PVE nodes (frr-pve.conf.j2).
#
# Naming alignment:
#   FRR peer-group EDGE4 <-> ROS connection EDGE4 (IPv4 loopback-to-loopback)
#   FRR peer-group EDGE6 <-> ROS connection EDGE6 (IPv6 loopback-to-loopback)
#   FRR AS 4200001000    <-> ROS remote.as 4200001000
#   ROS AS 4200000000    <-> FRR EDGE_AS 4200000000
#
# Usage:
#   ./configure-routeros.sh
#
# Prerequisites:
#   - SSH access to RouterOS device
#   - OSPF underlay already configured (loopbacks reachable)
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration - aligned with FRR template defaults
ROUTEROS_HOST="${ROUTEROS_HOST:-10.30.0.254}"
ROUTEROS_USER="${ROUTEROS_USER:-admin}"

# ASNs - must match frr-pve.conf.j2
EDGE_AS="4200000000"     # ROS local AS (FRR: EDGE_AS)
PVE_AS="4200001000"      # PVE FRR AS  (FRR: LOCAL_AS)

# Loopback addresses - must match FRR template
ROS_LOOPBACK_V4="10.255.0.254"            # ROS lo (FRR: EDGE_V4)
ROS_LOOPBACK_V6="fd00:0:0:ffff::fffe"     # ROS lo (FRR: EDGE_V6)

# PVE node infra loopbacks (FRR: infra_ip4 / infra_ip6)
# Used as listen ranges for dynamic peering
PVE_LISTEN_V4="10.255.0.0/24"
PVE_LISTEN_V6="fd00:0:0:ffff::/64"

log_info "========================================="
log_info "  RouterOS BGP Configuration (PVE Fabric)"
log_info "========================================="
log_info "RouterOS Host:   ${ROUTEROS_HOST}"
log_info "EDGE AS (ROS):   ${EDGE_AS}"
log_info "PVE AS (FRR):    ${PVE_AS}"
log_info "ROS Loopback v4: ${ROS_LOOPBACK_V4}"
log_info "ROS Loopback v6: ${ROS_LOOPBACK_V6}"
log_info "========================================="

# Check SSH connectivity
log_info ""
log_info "Checking RouterOS connectivity..."
if ! ssh -o ConnectTimeout=5 "${ROUTEROS_USER}@${ROUTEROS_HOST}" /system/resource/print &>/dev/null; then
    log_error "Cannot connect to RouterOS via SSH"
    exit 1
fi
log_success "RouterOS connection OK"

ros_cmd() {
    ssh "${ROUTEROS_USER}@${ROUTEROS_HOST}" "$@"
}

# Configure BGP instance
log_info ""
log_info "Configuring BGP instance..."
ros_cmd "/routing/bgp/instance/add name=PVE_FABRIC as=${EDGE_AS} router-id=${ROS_LOOPBACK_V4}" 2>/dev/null || true
log_success "BGP instance configured"

# Configure BGP connections (dynamic listeners matching FRR peer-group names)
log_info ""
log_info "Configuring BGP connections..."

# EDGE4 - IPv4 eBGP (loopback-to-loopback, multihop)
# Matches FRR: neighbor EDGE4 peer-group
log_info "Adding EDGE4 (IPv4 eBGP)..."
ros_cmd "/routing/bgp/connection/add \
    name=EDGE4 \
    instance=PVE_FABRIC \
    remote.address=${PVE_LISTEN_V4} remote.as=${PVE_AS} \
    local.address=${ROS_LOOPBACK_V4} local.role=ebgp \
    connect=no listen=yes \
    multihop=yes \
    hold-time=30s keepalive-time=10s \
    afi=ip \
    output.redistribute=connected,static output.default-originate=always" 2>/dev/null || true

# EDGE6 - IPv6 eBGP (loopback-to-loopback, multihop)
# Matches FRR: neighbor EDGE6 peer-group
log_info "Adding EDGE6 (IPv6 eBGP)..."
ros_cmd "/routing/bgp/connection/add \
    name=EDGE6 \
    instance=PVE_FABRIC \
    remote.address=${PVE_LISTEN_V6} remote.as=${PVE_AS} \
    local.address=${ROS_LOOPBACK_V6} local.role=ebgp \
    connect=no listen=yes \
    multihop=yes \
    hold-time=30s keepalive-time=10s \
    afi=ipv6 \
    output.redistribute=connected,static,bgp output.default-originate=always" 2>/dev/null || true

log_success "BGP connections configured"

# Verify BGP sessions
log_info ""
log_info "Verifying BGP sessions..."
sleep 5

BGP_STATUS=$(ros_cmd "/routing/bgp/session/print where established" 2>/dev/null || echo "")

if [[ -n "$BGP_STATUS" ]]; then
    log_success "BGP sessions established:"
    echo "$BGP_STATUS"
else
    log_warn "No established BGP sessions found yet"
    log_warn "Sessions will establish once OSPF learns loopback routes"
fi

# Display summary
log_info ""
log_info "========================================="
log_success "RouterOS BGP Configuration Complete"
log_info "========================================="
log_info ""
log_info "Naming alignment with FRR:"
log_info "  ROS instance PVE_FABRIC  <-> FRR router bgp ${PVE_AS}"
log_info "  ROS conn EDGE4           <-> FRR peer-group EDGE4"
log_info "  ROS conn EDGE6           <-> FRR peer-group EDGE6"
log_info ""
log_info "Verification commands:"
log_info "  ssh ${ROUTEROS_USER}@${ROUTEROS_HOST}"
log_info "  /routing/bgp/session/print"
log_info "  /ip/route/print where bgp"
log_info "  /ipv6/route/print where bgp"
log_info "========================================="
