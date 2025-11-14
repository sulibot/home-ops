#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# generate-talenv.sh - Generate Talos environment configuration from Terraform
# ============================================================================
#
# This script generates a talenv.sops.yaml file for a Talos Linux cluster
# by fetching infrastructure outputs from Terraform/Terragrunt and encrypting
# them with SOPS for secure storage in git.
#
# Usage:
#   ./generate-talenv.sh <cluster_id> <output_dir>
#
# Examples:
#   ./generate-talenv.sh 101 kubernetes/clusters/cluster-101
#   ./generate-talenv.sh 102 kubernetes/clusters/cluster-102
#
# Requirements:
#   - terragrunt (for Terraform wrapper)
#   - yq (for YAML processing)
#   - sops (for encryption)
#   - Terraform state must exist (run 'terragrunt apply' first)
#
# ============================================================================

# Color output helpers
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error()   { echo -e "${RED}✗${NC} $*" >&2; }

# ============================================================================
# Validation
# ============================================================================

# Check arguments
if [ "$#" -ne 2 ]; then
    log_error "Invalid number of arguments"
    echo ""
    echo "Usage: $0 <cluster_id> <output_dir>"
    echo ""
    echo "Arguments:"
    echo "  cluster_id   - Numeric cluster identifier (e.g., 101, 102)"
    echo "  output_dir   - Directory where talenv.sops.yaml will be created"
    echo ""
    echo "Example:"
    echo "  $0 101 kubernetes/clusters/cluster-101"
    exit 1
fi

readonly CLUSTER_ID="$1"
readonly OUTPUT_DIR="$2"
readonly TERRAFORM_DIR="tf/infra/live/cluster-sol/nodes"
readonly TALENV_FILE="${OUTPUT_DIR}/talenv.sops.yaml"

# Validate cluster ID format
if ! [[ "$CLUSTER_ID" =~ ^[0-9]+$ ]]; then
    log_error "Cluster ID must be numeric (got: $CLUSTER_ID)"
    exit 1
fi

# Check required tools
check_dependencies() {
    local missing_deps=()

    for cmd in terragrunt yq sops; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo "Install missing tools:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                terragrunt) echo "  brew install terragrunt" ;;
                yq)         echo "  brew install yq" ;;
                sops)       echo "  brew install sops" ;;
            esac
        done
        exit 1
    fi
}

check_dependencies

# Check if Terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    log_error "Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# ============================================================================
# Fetch Terraform Outputs
# ============================================================================

log_info "Generating talenv for cluster-${CLUSTER_ID}"
echo ""

# Fetch node information
log_info "Fetching node information from Terraform..."
if ! nodes_json=$(cd "$TERRAFORM_DIR" && NO_COLOR=1 terragrunt output -json talhelper_env 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | grep -A 999999 '^{'); then
    log_error "Failed to fetch node information from Terraform"
    log_error "Ensure 'terragrunt apply' has been run in: $TERRAFORM_DIR"
    echo ""
    echo "Raw output (first 500 chars):"
    cd "$TERRAFORM_DIR" && NO_COLOR=1 terragrunt output -json talhelper_env 2>&1 | head -c 500
    exit 1
fi

nodes_yaml=$(echo "$nodes_json" | yq -P 'to_entries | map(.value)')
node_count=$(echo "$nodes_yaml" | yq 'length')
log_success "Found $node_count nodes"

# Fetch network CIDR information
log_info "Fetching network CIDR information from Terraform..."
if k8s_cidrs_json=$(cd "$TERRAFORM_DIR" && NO_COLOR=1 terragrunt output -json k8s_network_config 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' | grep -A 999999 '^{'); then
    k8s_cidrs_yaml=$(echo "$k8s_cidrs_json" | yq eval -P)
    log_success "Retrieved network configuration from Terraform state"
else
    log_warning "k8s_network_config output not found in Terraform state"
    log_warning "Using default network CIDRs for cluster-${CLUSTER_ID}"
    log_info "To use Terraform-managed values, run: cd $TERRAFORM_DIR && terragrunt apply"

    # Generate default CIDRs based on cluster ID
    k8s_cidrs_yaml=$(cat <<DEFAULTS
pods_ipv4: "10.${CLUSTER_ID}.0.0/16"
pods_ipv6: "fd00:${CLUSTER_ID}:1::/60"
services_ipv4: "10.${CLUSTER_ID}.96.0/20"
services_ipv6: "fd00:${CLUSTER_ID}:96::/108"
loadbalancers_ipv4: "10.${CLUSTER_ID}.27.0/24"
loadbalancers_ipv6: "fd00:${CLUSTER_ID}:1b::/120"
DEFAULTS
)
fi

# ============================================================================
# Generate Combined YAML
# ============================================================================

log_info "Combining data into unified YAML structure..."

# Calculate VIP address (first IP in public range)
readonly VIP_ADDRESS="10.${CLUSTER_ID}.0.1"

combined_yaml=$(cat <<EOF
# Talos Environment Configuration for cluster-${CLUSTER_ID}
# Generated by: $0
# Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

clusterName: "cluster-${CLUSTER_ID}"
endpoint: "https://${VIP_ADDRESS}:6443"

# Kubernetes Network CIDRs
${k8s_cidrs_yaml}

# Cluster Nodes
nodes:
${nodes_yaml}
EOF
)

# ============================================================================
# Encrypt with SOPS
# ============================================================================

log_info "Encrypting configuration file with SOPS..."

# Check if SOPS config exists
if [ ! -f ".sops.yaml" ]; then
    log_warning "No .sops.yaml configuration found in repository root"
    log_warning "SOPS will use default encryption settings"
fi

# Write unencrypted YAML temporarily, then encrypt in place
# SOPS needs the file path to determine which creation rules to apply
# Use a filename that matches SOPS creation rules (*.sops.yaml)
temp_file="${OUTPUT_DIR}/talenv-unencrypted.sops.yaml"
echo "$combined_yaml" > "$temp_file"

# Set SOPS AGE key file if not already set
if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "$HOME/.config/sops/age/keys.txt" ]; then
    export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
fi

# Encrypt the file (SOPS will read the file path to apply the correct rules from .sops.yaml)
sops_error=$(sops --encrypt --input-type yaml --output-type yaml "$temp_file" 2>&1 > "$TALENV_FILE")
sops_exit_code=$?

if [ $sops_exit_code -eq 0 ]; then
    rm -f "$temp_file"
    log_success "Successfully encrypted configuration"
else
    log_error "Failed to encrypt configuration with SOPS"
    echo ""
    echo "Error details:"
    echo "$sops_error"
    echo ""
    echo "SOPS may require the AGE key to be available."
    echo "Make sure SOPS_AGE_KEY_FILE or SOPS_AGE_KEY environment variable is set."
    rm -f "$temp_file"
    exit 1
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
log_success "Generated encrypted configuration: $TALENV_FILE"
echo ""
echo "Summary:"
echo "  Cluster ID:       $CLUSTER_ID"
echo "  Cluster Name:     cluster-${CLUSTER_ID}"
echo "  API Endpoint:     https://${VIP_ADDRESS}:6443"
echo "  Node Count:       $node_count"
echo "  Output File:      $TALENV_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the configuration: sops $TALENV_FILE"
echo "  2. Commit to git:            git add $TALENV_FILE && git commit -m 'Add talenv for cluster-${CLUSTER_ID}'"
echo "  3. Use with talhelper:       talhelper genconfig --config-file $TALENV_FILE"
echo ""
