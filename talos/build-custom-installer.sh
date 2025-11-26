#!/usr/bin/env bash
set -euo pipefail

# Build a custom Talos installer image with FRR extension
# This creates an installer that includes the FRR routing extension

TALOS_VERSION="v1.11.5"
FRR_EXTENSION="ghcr.io/jsenecal/frr-talos-extension:latest"
SCHEMATIC_ID=$(cd ../terraform/infra/live/cluster-101/install-schematic && terragrunt output -raw schematic_id)

# Output directory for the installer image
OUTPUT_DIR="_out"
mkdir -p "${OUTPUT_DIR}"

echo "Building custom Talos installer v${TALOS_VERSION} with FRR extension..."
echo "Schematic ID: ${SCHEMATIC_ID}"
echo "FRR Extension: ${FRR_EXTENSION}"

# Build the installer using Talos imager
docker run --rm \
  -v "${PWD}/${OUTPUT_DIR}:/out" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "ghcr.io/siderolabs/imager:${TALOS_VERSION}" \
  installer \
  --arch amd64 \
  --platform metal \
  --base-installer-image "ghcr.io/siderolabs/installer:${TALOS_VERSION}" \
  --system-extension-image "${FRR_EXTENSION}"

echo ""
echo "Custom installer built successfully!"
echo "Installer image: ${OUTPUT_DIR}/installer-amd64.tar"
echo ""
echo "Next steps:"
echo "1. Load the image: docker load < ${OUTPUT_DIR}/installer-amd64.tar"
echo "2. Tag it: docker tag <image-id> your-registry/talos-installer-frr:${TALOS_VERSION}"
echo "3. Push it: docker push your-registry/talos-installer-frr:${TALOS_VERSION}"
echo "4. Update Terraform to use the custom installer image"
