#!/bin/bash
#
# Prefer GUA over ULA for IPv6 masquerading
# This script ensures Global Unicast Addresses (GUA) are listed before
# Unique Local Addresses (ULA) on eth0, which affects Cilium's BPF masquerading
# source IP selection.
#

set -e

INTERFACE="eth0"
LOG_TAG="prefer-gua-ipv6"

log() {
    logger -t "$LOG_TAG" "$@"
    echo "[$(date -Iseconds)] $@"
}

# Wait for interface to be up
if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
    log "ERROR: Interface $INTERFACE not found"
    exit 1
fi

# Get ULA addresses (fd00::/8)
ULA_ADDRS=$(ip -6 addr show dev "$INTERFACE" | grep 'inet6 fd00:' | awk '{print $2}')

if [ -z "$ULA_ADDRS" ]; then
    log "No ULA addresses found on $INTERFACE, nothing to do"
    exit 0
fi

# Get GUA addresses (2000::/3) - matches addresses starting with 2 or 3
GUA_ADDRS=$(ip -6 addr show dev "$INTERFACE" | grep -E 'inet6 [23][0-9a-f]{3}:' | awk '{print $2}')

if [ -z "$GUA_ADDRS" ]; then
    log "No GUA addresses found on $INTERFACE yet, will retry later"
    exit 0
fi

log "Found ULA addresses: $ULA_ADDRS"
log "Found GUA addresses: $GUA_ADDRS"

# Check current order - if GUA is already first, nothing to do
FIRST_ADDR=$(ip -6 addr show dev "$INTERFACE" | grep -E 'inet6 (fd00:|[23][0-9a-f]{3}:)' | head -1 | awk '{print $2}')

if echo "$FIRST_ADDR" | grep -qE '^[23][0-9a-f]{3}:'; then
    log "GUA address is already first ($FIRST_ADDR), nothing to do"
    exit 0
fi

log "Reordering addresses to prefer GUA over ULA"

# Remove all addresses (except link-local)
for addr in $GUA_ADDRS; do
    log "Removing GUA address: $addr"
    ip -6 addr del "$addr" dev "$INTERFACE" || true
done

for addr in $ULA_ADDRS; do
    log "Removing ULA address: $addr"
    ip -6 addr del "$addr" dev "$INTERFACE" || true
done

# Re-add in correct order: GUA first, then ULA
for addr in $GUA_ADDRS; do
    log "Re-adding GUA address: $addr"
    ip -6 addr add "$addr" dev "$INTERFACE" || true
done

for addr in $ULA_ADDRS; do
    log "Re-adding ULA address: $addr"
    ip -6 addr add "$addr" dev "$INTERFACE" || true
done

log "Address reordering complete"

# Verify new order
log "New address order:"
ip -6 addr show dev "$INTERFACE" | grep -E 'inet6 (fd00:|[23][0-9a-f]{3}:)' | logger -t "$LOG_TAG"

exit 0
