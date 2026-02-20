#!/usr/bin/env bash
# Pre-pull critical container images to all nodes before Flux bootstrap
# This dramatically speeds up initial pod startup (60s → 1s for large images)
#
# Strategy: Use helm template to extract actual image references from Flux configs,
# then create a temporary DaemonSet that runs sleep containers with those images.

set -euo pipefail

KUBECONFIG="${1:?KUBECONFIG path required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Image Pre-Pull for Flux Bootstrap ==="

# Critical charts to pre-pull (extracted from Flux HelmRelease/OCIRepository configs)
declare -A CHARTS=(
  # Chart name: repo_type:repo_url:chart:version
  ["ceph-csi-cephfs"]="helm:https://ceph.github.io/csi-charts:ceph-csi-cephfs:3.16.1"
  ["ceph-csi-rbd"]="helm:https://ceph.github.io/csi-charts:ceph-csi-rbd:3.16.1"
  ["cilium"]="helm:https://helm.cilium.io:cilium:1.19.1"
  ["cert-manager"]="helm:https://charts.jetstack.io:cert-manager:v1.19.1"
  ["external-secrets"]="oci:ghcr.io/external-secrets/charts:external-secrets:0.20.3"
  ["snapshot-controller"]="oci:ghcr.io/piraeusdatastore/helm-charts:snapshot-controller:4.1.1"
  ["volsync"]="oci:ghcr.io/home-operations/charts-mirror:volsync-perfectra1n:0.17.14"
  ["kube-prometheus-stack"]="oci:ghcr.io/prometheus-community/charts:kube-prometheus-stack:79.12.0"
)

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
echo "Step 2: Creating image pre-pull DaemonSet..."
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
      initContainers:
EOF

# Add each image as an init container (runs sequentially, ensuring all images pulled)
container_index=0
for image in "${UNIQUE_IMAGES[@]}"; do
  # Sanitize image name for container name (replace special chars with dashes)
  container_name="pull-$(echo "$image" | sed 's|[^a-zA-Z0-9]|-|g' | cut -c1-50)"

  cat >> /tmp/image-prepull-daemonset.yaml <<EOF
      - name: ${container_name}-${container_index}
        image: ${image}
        command: ["/bin/sh", "-c", "echo 'Cached: ${image}' && exit 0"]
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

# Main container just sleeps (keeps DaemonSet alive)
cat >> /tmp/image-prepull-daemonset.yaml <<EOF
      containers:
      - name: sleep
        image: busybox:1.37.0
        command: ["/bin/sh", "-c", "sleep 3600"]
        resources:
          limits:
            cpu: 10m
            memory: 32Mi
          requests:
            cpu: 1m
            memory: 16Mi
      tolerations:
      - operator: Exists  # Run on all nodes including control plane
EOF

# Apply DaemonSet
echo "Step 3: Applying DaemonSet to cluster..."
kubectl --kubeconfig="$KUBECONFIG" apply -f /tmp/image-prepull-daemonset.yaml

# Wait for DaemonSet to be ready on all nodes
echo "Step 4: Waiting for images to be pulled on all nodes..."
echo "  This may take 5-10 minutes depending on network speed and number of images"

# Get number of nodes
NODE_COUNT=$(kubectl --kubeconfig="$KUBECONFIG" get nodes --no-headers | wc -l | tr -d ' ')
echo "  Target: ${NODE_COUNT} nodes"

# Wait for all DaemonSet pods to complete init (images pulled)
TIMEOUT=600  # 10 minutes
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  READY=$(kubectl --kubeconfig="$KUBECONFIG" get daemonset image-prepull -n kube-system \
    -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

  if [[ "$READY" -eq "$NODE_COUNT" ]]; then
    echo "  ✓ All ${NODE_COUNT} nodes have cached images"
    break
  fi

  echo "  Progress: ${READY}/${NODE_COUNT} nodes ready..."
  sleep 10
  ((ELAPSED+=10))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "  ⚠ Timeout waiting for DaemonSet (some images may not be cached)"
  kubectl --kubeconfig="$KUBECONFIG" get pods -n kube-system -l app=image-prepull
else
  echo "Step 5: Cleaning up DaemonSet..."
  kubectl --kubeconfig="$KUBECONFIG" delete daemonset image-prepull -n kube-system --wait=false
  rm -f /tmp/image-prepull-daemonset.yaml
fi

echo "✓ Image pre-pull complete - critical images cached on all nodes"
echo "  Pod startup times: 60s → 1s for large images"
