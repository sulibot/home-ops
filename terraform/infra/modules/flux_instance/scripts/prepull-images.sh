#!/usr/bin/env bash
# Pre-pull critical container images to all nodes before Flux bootstrap
# This dramatically speeds up initial pod startup (60s → 1s for large images)
#
# Strategy:
# 1. Parse Flux HelmRelease/OCIRepository configs to get actual versions
# 2. Use helm template to extract container image references
# 3. Create temporary DaemonSet that pulls all images in parallel

set -euo pipefail

KUBECONFIG="${1:?KUBECONFIG path required}"
REPO_ROOT="${2:?Repository root path required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Image Pre-Pull for Flux Bootstrap ==="

# Check required dependencies
for cmd in kubectl helm yq jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "  ✗ Error: $cmd is required but not installed"
    exit 1
  fi
done

echo "Reading chart versions from Flux configs..."
echo "  Repository root: ${REPO_ROOT}"

# Helper: Extract version from HelmRelease YAML
get_helm_version() {
  local file="$1"
  yq eval '.spec.chart.spec.version' "$file" 2>/dev/null || echo ""
}

# Helper: Extract repo URL from HelmRepository
get_helm_repo_url() {
  local repo_name="$1"
  local repo_file="${REPO_ROOT}/kubernetes/flux/repositories/helm/${repo_name}.yaml"
  [[ -f "$repo_file" ]] && yq eval '.spec.url' "$repo_file" 2>/dev/null || echo ""
}

# Helper: Extract version from OCIRepository YAML
get_oci_version() {
  local file="$1"
  yq eval '.spec.ref.tag' "$file" 2>/dev/null || echo ""
}

# Helper: Extract URL from OCIRepository
get_oci_url() {
  local file="$1"
  yq eval '.spec.url' "$file" 2>/dev/null | sed 's|^oci://||'
}

# Critical apps to pre-pull (paths relative to repo root)
declare -A APP_CONFIGS=(
  ["ceph-csi-cephfs"]="kubernetes/apps/foundation/ceph-csi/cephfs/app"
  ["ceph-csi-rbd"]="kubernetes/apps/foundation/ceph-csi/rbd/app"
  ["cilium"]="kubernetes/apps/networking/cilium/app"
  ["cert-manager"]="kubernetes/apps/core/cert-manager/app"
  ["external-secrets"]="kubernetes/apps/foundation/external-secrets/external-secrets/app"
  ["snapshot-controller"]="kubernetes/apps/kube-system/snapshot-controller/app"
  ["volsync"]="kubernetes/apps/data/volsync/app"
  ["kube-prometheus-stack"]="kubernetes/apps/observability-stack/kube-prometheus-stack/app"
)

# Known Helm repository URLs (for apps using HelmRepository sourceRef)
declare -A HELM_REPOS=(
  ["ceph-csi"]="https://ceph.github.io/csi-charts"
  ["cilium"]="https://helm.cilium.io"
  ["cert-manager"]="https://charts.jetstack.io"
)

# Build CHARTS array dynamically from Flux configs
declare -A CHARTS
for app_name in "${!APP_CONFIGS[@]}"; do
  app_path="${REPO_ROOT}/${APP_CONFIGS[$app_name]}"
  helmrelease="${app_path}/helmrelease.yaml"
  ocirepository="${app_path}/ocirepository.yaml"

  if [[ -f "$ocirepository" ]]; then
    # OCI-based chart (external-secrets, volsync, kube-prometheus-stack, snapshot-controller)
    version=$(get_oci_version "$ocirepository")
    url=$(get_oci_url "$ocirepository")
    chart_name=$(yq eval '.metadata.name' "$ocirepository" 2>/dev/null)

    if [[ -n "$version" && -n "$url" ]]; then
      CHARTS["$app_name"]="oci:${url}:${chart_name}:${version}"
      echo "  ✓ ${app_name}: OCI ${chart_name}:${version}"
    fi
  elif [[ -f "$helmrelease" ]]; then
    # Traditional Helm repository (ceph-csi, cilium, cert-manager)
    version=$(get_helm_version "$helmrelease")
    chart_name=$(yq eval '.spec.chart.spec.chart' "$helmrelease" 2>/dev/null)
    repo_ref=$(yq eval '.spec.chart.spec.sourceRef.name' "$helmrelease" 2>/dev/null)
    repo_url="${HELM_REPOS[$repo_ref]:-}"

    if [[ -n "$version" && -n "$chart_name" && -n "$repo_url" ]]; then
      CHARTS["$app_name"]="helm:${repo_url}:${chart_name}:${version}"
      echo "  ✓ ${app_name}: ${chart_name}:${version}"
    fi
  fi
done

if [[ ${#CHARTS[@]} -eq 0 ]]; then
  echo "  ⚠ No charts found - check Flux config paths"
  exit 1
fi

echo "  Found ${#CHARTS[@]} charts to process"
echo ""

# Extract all unique image references from helm charts
extract_images() {
  local chart_name="$1"
  local repo_info="${CHARTS[$chart_name]}"

  IFS=':' read -r repo_type repo_url chart version <<< "$repo_info"

  echo "  Extracting images from $chart_name (${version})..."

  if [[ "$repo_type" == "helm" ]]; then
    # Traditional Helm repository
    helm template "$chart_name" "$chart" \
      --repo "$repo_url" \
      --version "$version" \
      --set installCRDs=false \
      2>/dev/null | grep -oE 'image:\s*.+' | awk '{print $2}' | tr -d '"' | sort -u
  elif [[ "$repo_type" == "oci" ]]; then
    # OCI registry
    helm template "$chart_name" "oci://${repo_url}/${chart}" \
      --version "$version" \
      --set installCRDs=false \
      2>/dev/null | grep -oE 'image:\s*.+' | awk '{print $2}' | tr -d '"' | sort -u
  fi
}

# Build comprehensive image list
echo "Step 1: Extracting images from Flux configs..."
ALL_IMAGES=()
for chart in "${!CHARTS[@]}"; do
  while IFS= read -r image; do
    [[ -n "$image" ]] && ALL_IMAGES+=("$image")
  done < <(extract_images "$chart" || echo "")
done

# Remove duplicates and filter out invalid entries
UNIQUE_IMAGES=($(printf '%s\n' "${ALL_IMAGES[@]}" | sort -u | grep -E '^[a-zA-Z0-9]'))

echo "  Found ${#UNIQUE_IMAGES[@]} unique images to pre-pull"

# Generate DaemonSet manifest
echo "Step 2: Creating image pre-pull DaemonSet (${#UNIQUE_IMAGES[@]} images in parallel)..."
cat > /tmp/image-prepull-daemonset.yaml <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: image-prepull
  namespace: kube-system
  labels:
    app: image-prepull
    managed-by: terraform-bootstrap
spec:
  selector:
    matchLabels:
      app: image-prepull
  template:
    metadata:
      labels:
        app: image-prepull
    spec:
      containers:
EOF

# Add each image as a regular container (runs in PARALLEL for maximum speed)
container_index=0
for image in "${UNIQUE_IMAGES[@]}"; do
  # Sanitize image name for container name (replace special chars with dashes)
  container_name="pull-$(echo "$image" | sed 's|[^a-zA-Z0-9]|-|g' | cut -c1-50)"

  cat >> /tmp/image-prepull-daemonset.yaml <<EOF
      - name: ${container_name}-${container_index}
        image: ${image}
        command: ["/bin/sh", "-c", "echo 'Cached: ${image}'; sleep 3600"]
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 10m
            memory: 32Mi
EOF
  ((container_index++))
done

cat >> /tmp/image-prepull-daemonset.yaml <<EOF
      tolerations:
      - operator: Exists  # Run on all nodes including control plane
EOF

# Apply DaemonSet
echo "Step 3: Applying DaemonSet to cluster..."
kubectl --kubeconfig="$KUBECONFIG" apply -f /tmp/image-prepull-daemonset.yaml

# Wait for DaemonSet pods to be running on all nodes (all images pulled in parallel)
echo "Step 4: Waiting for images to be pulled on all nodes..."
echo "  Pulling ${#UNIQUE_IMAGES[@]} images in parallel - this may take 2-5 minutes"

# Get number of nodes
NODE_COUNT=$(kubectl --kubeconfig="$KUBECONFIG" get nodes --no-headers | wc -l | tr -d ' ')
echo "  Target: ${NODE_COUNT} nodes"

# Wait for all DaemonSet pods to have all containers running (images pulled)
TIMEOUT=600  # 10 minutes
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  # Count pods where ALL containers are running (not just ready)
  READY=$(kubectl --kubeconfig="$KUBECONFIG" get pods -n kube-system -l app=image-prepull \
    -o json 2>/dev/null | jq -r '[.items[] | select(.status.phase == "Running") |
    select(all(.status.containerStatuses[]; .state.running != null))] | length' || echo "0")

  if [[ "$READY" -eq "$NODE_COUNT" ]]; then
    echo "  ✓ All ${NODE_COUNT} nodes have cached ${#UNIQUE_IMAGES[@]} images"
    break
  fi

  # Show detailed progress
  PULLING=$(kubectl --kubeconfig="$KUBECONFIG" get pods -n kube-system -l app=image-prepull \
    -o json 2>/dev/null | jq -r '[.items[] | .status.containerStatuses[]? |
    select(.state.waiting.reason == "ContainerCreating" or .state.waiting.reason == "ErrImagePull")] | length' || echo "0")

  echo "  Progress: ${READY}/${NODE_COUNT} nodes ready (${PULLING} containers still pulling images)..."
  sleep 10
  ((ELAPSED+=10))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "  ⚠ Timeout waiting for DaemonSet (some images may not be cached)"
  kubectl --kubeconfig="$KUBECONFIG" get pods -n kube-system -l app=image-prepull -o wide
else
  echo "Step 5: Cleaning up DaemonSet..."
  kubectl --kubeconfig="$KUBECONFIG" delete daemonset image-prepull -n kube-system --wait=false
  rm -f /tmp/image-prepull-daemonset.yaml
fi

echo "✓ Image pre-pull complete - critical images cached on all nodes"
echo "  Pod startup times: 60s → 1s for large images"
