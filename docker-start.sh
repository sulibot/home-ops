#!/bin/bash

set -e

log() {
    echo -e "[$(date +%Y-%m-%d-%H:%M:%S)][frr] $*" >&2
}

FRR_RUNTIME_DIRS=(/run/frr /run/frr-lib /run/frr-tmp /run/frr-log)
for dir in "${FRR_RUNTIME_DIRS[@]}"; do
    mkdir -p "$dir"
    chown frr:frr "$dir" >/dev/null 2>&1 || true
done

export FRR_RUN_DIR=/run/frr
export FRR_RUNDIR=/run/frr
export FRR_STATE_DIR=/run/frr-lib
export FRR_LIB_DIR=/run/frr-lib
export FRR_TMP_DIR=/run/frr-tmp
export FRR_LOG_DIR=/run/frr-log
export FRR_LOGDIR=/run/frr-log
export ZEBRA_PID_FILE=/run/frr/zebra.pid
export BGPD_PID_FILE=/run/frr/bgpd.pid
export BFDD_PID_FILE=/run/frr/bfdd.pid

# Load configuration from files only
log "Loading configuration from files..."

# Validate and load configuration
log "Validating configuration"
python3 /usr/local/bin/config_loader.py --validate || {
    log "Configuration validation failed"
    exit 1
}

log "Generating configuration context"
python3 /usr/local/bin/config_loader.py --json > /tmp/config.json
CONFIG_SOURCE="/tmp/config.json"

log "Configuration loaded from: ${CONFIG_SOURCE}"

FRR_TEMPLATE="/etc/frr/frr.conf.j2"
log "Using FRR template: ${FRR_TEMPLATE}"

log "Setting up network with namespace isolation"

# --- Extract network configuration from JSON ---
VETH_FRR=$(python3 -c "import json; c=json.load(open('/tmp/config.json')); print(c.get('network',{}).get('veth_names',{}).get('frr_side','veth-frr'))")
VETH_CILIUM=$(python3 -c "import json; c=json.load(open('/tmp/config.json')); print(c.get('network',{}).get('veth_names',{}).get('cilium_side','veth-cilium'))")
INTERFACE_MTU=$(python3 -c "import json; c=json.load(open('/tmp/config.json')); print(c.get('network',{}).get('interface_mtu',1500))")

# Cilium peering IPs (MP-BGP over IPv6)
CILIUM_PEER_IPV6_LOCAL=$(python3 -c "import json; c=json.load(open('/tmp/config.json')); print(c.get('bgp',{}).get('cilium',{}).get('peering',{}).get('ipv6',{}).get('local',''))")
CILIUM_PEER_IPV6_REMOTE=$(python3 -c "import json; c=json.load(open('/tmp/config.json')); print(c.get('bgp',{}).get('cilium',{}).get('peering',{}).get('ipv6',{}).get('remote',''))")
CILIUM_PEER_IPV6_PREFIX=$(python3 -c "import json; c=json.load(open('/tmp/config.json')); print(c.get('bgp',{}).get('cilium',{}).get('peering',{}).get('ipv6',{}).get('prefix',126))")

# --- Veth Pair Setup in Host Namespace ---
log "Ensuring veth pair ${VETH_FRR} <-> ${VETH_CILIUM} exists in host namespace"

if ! /sbin/ip link show ${VETH_FRR} >/dev/null 2>&1; then
    log "Creating veth pair ${VETH_CILIUM} <-> ${VETH_FRR}"
    /sbin/ip link add ${VETH_CILIUM} type veth peer name ${VETH_FRR} || true
fi

# Configure FRR side (veth-frr)
log "Configuring FRR side IPv6: ${CILIUM_PEER_IPV6_REMOTE}/${CILIUM_PEER_IPV6_PREFIX} on ${VETH_FRR}"
/sbin/ip -6 addr add ${CILIUM_PEER_IPV6_REMOTE}/${CILIUM_PEER_IPV6_PREFIX} dev ${VETH_FRR} || true
/sbin/ip link set ${VETH_FRR} mtu ${INTERFACE_MTU} up

# Configure Cilium side (veth-cilium)
log "Configuring Cilium side IPv6: ${CILIUM_PEER_IPV6_LOCAL}/${CILIUM_PEER_IPV6_PREFIX} on ${VETH_CILIUM}"
/sbin/ip -6 addr add ${CILIUM_PEER_IPV6_LOCAL}/${CILIUM_PEER_IPV6_PREFIX} dev ${VETH_CILIUM} || true
/sbin/ip link set ${VETH_CILIUM} mtu ${INTERFACE_MTU} up

log "Network setup complete."

# Version-based initialization
CURRENT_VERSION=""
if [ -f /etc/frr.defaults/VERSION ]; then
    CURRENT_VERSION=$(cat /etc/frr.defaults/VERSION)
    log "Container version: ${CURRENT_VERSION}"
fi

INSTALLED_VERSION=""
if [ -f /etc/frr/.initialized ]; then
    INSTALLED_VERSION=$(cat /etc/frr/.initialized 2>/dev/null || echo "")
    log "Installed version: ${INSTALLED_VERSION}"
else
    log "No initialized marker found (first boot)"
fi

# Initialize or update if version mismatch or first boot
if [ "$CURRENT_VERSION" != "$INSTALLED_VERSION" ] || [ ! -f /etc/frr/.initialized ]; then
    if [ -z "$INSTALLED_VERSION" ]; then
        log "Initializing /etc/frr directory (first boot)"
    else
        log "Version mismatch detected (${INSTALLED_VERSION} -> ${CURRENT_VERSION})"
        log "Updating template and configuration files..."
    fi

    # Copy defaults from backup to mounted directory
    # Important: Copy template and daemons, but preserve frr.conf if it exists
    mkdir -p /etc/frr
    cp /etc/frr.defaults/frr.conf.j2 /etc/frr/frr.conf.j2 2>/dev/null || true
    cp /etc/frr.defaults/daemons /etc/frr/daemons 2>/dev/null || true
    cp /etc/frr.defaults/vtysh.conf /etc/frr/vtysh.conf 2>/dev/null || true
    cp /etc/frr.defaults/version /etc/frr/version 2>/dev/null || true

    # Write version to .initialized
    echo "${CURRENT_VERSION}" > /etc/frr/.initialized
    log "Initialized marker updated to version: ${CURRENT_VERSION}"
fi

# Ensure daemons file exists
if [ ! -f /etc/frr/daemons ]; then
    cp /etc/frr.defaults/daemons /etc/frr/daemons
fi

# Generate FRR configuration
log "Generating FRR configuration from template: ${FRR_TEMPLATE}"

# Use the JSON context from config_loader
python3 /usr/local/bin/render_template.py ${FRR_TEMPLATE} ${CONFIG_SOURCE} /etc/frr/frr.conf

log "Generated FRR configuration:"
cat /etc/frr/frr.conf

# Create vtysh.conf if it doesn't exist
[ -r /etc/frr/vtysh.conf ] || touch /etc/frr/vtysh.conf

# Set ownership
chown -R frr:frr /etc/frr || true

# Enable syslog
log "Starting syslogd"
syslogd -n -O - &

# Start FRR
log "Starting FRR daemons (including BFD if enabled)"
/usr/lib/frr/frrinit.sh start

# Wait for daemons to start
sleep 5

# Dump Cilium neighbor FSM state for troubleshooting
log "Dumping Cilium neighbor FSM state"
/usr/local/bin/dump-bgp-state.sh || true

# Check BFD status if configured
if grep -q "bfdd=true" /etc/frr/daemons 2>/dev/null; then
    log "Checking BFD daemon status"
    vtysh -c "show bfd peers" || true
fi

# Show process list
log "Current processes:"
ps -ef | grep -E "(bgpd|bfdd|zebra)" || true

# Monitoring loop with BFD status
MONITOR_INTERVAL=${MONITOR_INTERVAL:-60}
MONITOR_COUNT=${MONITOR_COUNT:-5}

count=0
while true; do
    if [ $count -lt ${MONITOR_COUNT} ]; then
        log "=== Status Check (${count}/${MONITOR_COUNT}) ==="

        # BGP status (MP-BGP includes both IPv4 and IPv6)
        vtysh -c "show bgp summary" || true

        # BFD status if configured
        if grep -q "bfdd=true" /etc/frr/daemons 2>/dev/null; then
            log "BFD Peer Status:"
            vtysh -c "show bfd peers brief" || true
        fi

        # Routing table
        vtysh -c "show ip route summary" || true

        if [ -n "${PEER_IPV6_REMOTE}" ]; then
            vtysh -c "show ipv6 route summary" || true
        fi

        count=$((count + 1))
    fi

    sleep ${MONITOR_INTERVAL}
done
