#!/bin/bash

# Talos node readiness checker
# Checks all cluster nodes before proceeding with bootstrap

set -euo pipefail

# Define nodes
declare -A NODES
NODES["solcp01"]="fd00:101::11"
NODES["solcp02"]="fd00:101::12"
NODES["solcp03"]="fd00:101::13"
NODES["solwk01"]="fd00:101::21"
NODES["solwk02"]="fd00:101::22"
NODES["solwk03"]="fd00:101::23"

MAX_RETRIES=60
RETRY_INTERVAL=5

echo "==================================="
echo "Talos Node Readiness Checker"
echo "==================================="
echo ""

check_node() {
    local name=$1
    local ip=$2

    if talosctl -n "$ip" version --client=false &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Main readiness loop
retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
    ready_count=0
    total_count=${#NODES[@]}

    echo -n "$(date '+%H:%M:%S') - Checking nodes: "

    for node_name in "${!NODES[@]}"; do
        node_ip="${NODES[$node_name]}"

        if check_node "$node_name" "$node_ip"; then
            echo -n "✓"
            ((ready_count++))
        else
            echo -n "✗"
        fi
    done

    echo " [$ready_count/$total_count ready]"

    # Check if all nodes are ready
    if [ $ready_count -eq $total_count ]; then
        echo ""
        echo "==================================="
        echo "✓ All $total_count nodes are ready!"
        echo "==================================="
        exit 0
    fi

    # Wait before next check
    ((retry_count++))
    if [ $retry_count -lt $MAX_RETRIES ]; then
        sleep $RETRY_INTERVAL
    fi
done

# Timeout reached
echo ""
echo "==================================="
echo "✗ Timeout: Not all nodes ready after $(($MAX_RETRIES * $RETRY_INTERVAL))s"
echo "==================================="
echo ""
echo "Node status:"
for node_name in "${!NODES[@]}"; do
    node_ip="${NODES[$node_name]}"
    if check_node "$node_name" "$node_ip"; then
        echo "  ✓ $node_name ($node_ip)"
    else
        echo "  ✗ $node_name ($node_ip)"
    fi
done
exit 1
