#!/bin/bash
set -e

echo "Destroying cluster 101 in proper order..."

# Destroy bootstrap first (has the most dependencies)
echo "=== Destroying bootstrap ==="
cd bootstrap && terragrunt destroy --auto-approve && cd ..

# Destroy config
echo "=== Destroying config ==="
cd config && terragrunt destroy --auto-approve && cd ..

# Destroy compute (VMs)
echo "=== Destroying compute ==="
cd compute && terragrunt destroy --auto-approve && cd ..

echo "✓ Cluster destroyed successfully"
