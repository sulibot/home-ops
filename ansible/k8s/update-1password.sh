#!/usr/bin/env bash
# Helper script to update 1Password Connect credentials
# This script provides a user-friendly interface to run the Ansible playbook

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  1Password Connect Credentials Update${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
}

check_requirements() {
    local missing_tools=()

    for tool in op sops kubectl flux git ansible-playbook; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install the missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                op)
                    echo "  - 1Password CLI: https://developer.1password.com/docs/cli/get-started"
                    ;;
                sops)
                    echo "  - SOPS: brew install sops"
                    ;;
                kubectl)
                    echo "  - kubectl: brew install kubectl"
                    ;;
                flux)
                    echo "  - Flux CLI: brew install fluxcd/tap/flux"
                    ;;
                ansible-playbook)
                    echo "  - Ansible: brew install ansible"
                    ;;
            esac
        done
        exit 1
    fi

    print_success "All required tools are installed"
}

check_env_vars() {
    local token_file="$SCRIPT_DIR/secrets/1password-token.sops.yaml"

    # Check if SOPS token file exists
    if [ -f "$token_file" ]; then
        print_success "Found SOPS-encrypted token file"
        print_info "Token will be loaded from: $token_file"
        return 0
    fi

    # Fall back to environment variable
    if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
        print_error "OP_SERVICE_ACCOUNT_TOKEN not found"
        echo ""
        echo "Please provide your 1Password Service Account token using one of these methods:"
        echo ""
        echo "Method 1: SOPS-encrypted file (RECOMMENDED)"
        echo "  1. Create the file: vim $token_file"
        echo "  2. Add content:"
        echo "     ---"
        echo "     op_service_account_token: ops_..."
        echo "  3. Encrypt: sops --encrypt --in-place $token_file"
        echo ""
        echo "Method 2: Environment variable"
        echo "  export OP_SERVICE_ACCOUNT_TOKEN='ops_...'"
        echo ""
        echo "  To make it persistent:"
        echo "  echo 'export OP_SERVICE_ACCOUNT_TOKEN=\"ops_...\"' >> ~/.zshrc"
        exit 1
    fi

    print_success "OP_SERVICE_ACCOUNT_TOKEN is set (from environment variable)"
    print_warning "Consider storing the token in a SOPS file instead: $token_file"
}

check_kubectl_context() {
    local context
    context=$(kubectl config current-context 2>/dev/null || echo "none")

    if [ "$context" = "none" ]; then
        print_error "No kubectl context is set"
        echo ""
        echo "Please configure kubectl to connect to your cluster"
        exit 1
    fi

    print_info "Current kubectl context: $context"

    read -p "Is this the correct cluster? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Aborted by user"
        exit 0
    fi
}

run_playbook() {
    print_info "Running Ansible playbook..."
    echo ""

    cd "$SCRIPT_DIR"

    if ansible-playbook playbooks/update-1password-credentials.yaml; then
        print_success "Playbook completed successfully!"
        return 0
    else
        print_error "Playbook failed"
        return 1
    fi
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Update 1Password Connect credentials for External Secrets.

This script automates the process of:
  1. Fetching credentials from 1Password vault
  2. Creating and encrypting the Kubernetes secret
  3. Committing and pushing to git
  4. Deploying via Flux
  5. Verifying the deployment

OPTIONS:
    -h, --help              Show this help message
    -c, --check             Only check requirements, don't run playbook
    -v, --verbose           Run ansible-playbook with verbose output
    --skip-checks           Skip all pre-flight checks (not recommended)

REQUIREMENTS:
    - OP_SERVICE_ACCOUNT_TOKEN environment variable must be set
    - Tools: op, sops, kubectl, flux, git, ansible-playbook
    - kubectl must be configured with the correct cluster context
    - The 1Password item must exist at: op://Kubernetes/1password-connect/credentials

EXAMPLES:
    # Normal run with all checks
    $(basename "$0")

    # Check requirements only
    $(basename "$0") --check

    # Verbose output for debugging
    $(basename "$0") --verbose

ENVIRONMENT VARIABLES:
    OP_SERVICE_ACCOUNT_TOKEN    1Password Service Account token (required)

For more information, see: ansible/k8s/README-1password.md
EOF
}

# Main script
main() {
    local check_only=false
    local verbose=false
    local skip_checks=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --skip-checks)
                skip_checks=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done

    print_header

    if [ "$skip_checks" = false ]; then
        print_info "Running pre-flight checks..."
        echo ""

        check_requirements
        check_env_vars

        if [ "$check_only" = false ]; then
            check_kubectl_context
        fi

        echo ""
        print_success "All pre-flight checks passed!"
        echo ""
    fi

    if [ "$check_only" = true ]; then
        print_info "Check-only mode - exiting"
        exit 0
    fi

    # Run the playbook
    if run_playbook; then
        echo ""
        print_success "1Password Connect credentials have been updated!"
        echo ""
        print_info "Next steps:"
        echo "  1. Verify External Secrets is working: kubectl get clustersecretstore"
        echo "  2. Test secret synchronization from 1Password"
        exit 0
    else
        echo ""
        print_error "Failed to update credentials"
        echo ""
        print_info "For troubleshooting:"
        echo "  - Check pod logs: kubectl logs -n external-secrets -l app.kubernetes.io/name=onepassword"
        echo "  - Check ClusterSecretStore: kubectl describe clustersecretstore onepassword-connect"
        echo "  - Run with verbose: $0 --verbose"
        exit 1
    fi
}

# Run main function
main "$@"
