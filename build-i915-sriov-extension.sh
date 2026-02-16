#!/bin/bash
set -euo pipefail

# Build i915-sriov extension for Talos 1.12.1
# Run this on debtest01 (10.101.0.41)

TALOS_VERSION="1.12.1"
EXTENSION_NAME="i915-sriov"
BUILD_DIR="/root/talos-extensions"
OUTPUT_DIR="/root/talos-extensions/output"

echo "=== Building i915-sriov Talos Extension for v${TALOS_VERSION} ==="

# Create build directories
mkdir -p ${BUILD_DIR} ${OUTPUT_DIR}
cd ${BUILD_DIR}

# Install required tools
echo "Installing build dependencies..."
apt-get update
apt-get install -y \
    docker.io \
    git \
    build-essential \
    wget \
    jq

# Clone i915-sriov-dkms source
if [ ! -d "i915-sriov-dkms" ]; then
    echo "Cloning i915-sriov-dkms..."
    git clone https://github.com/strongtz/i915-sriov-dkms.git
fi

# Get Talos kernel version for 1.12.1
# Talos 1.12.1 uses kernel 6.12.6
KERNEL_VERSION="6.12.6"
echo "Target kernel version: ${KERNEL_VERSION}"

# Create Dockerfile for building the extension
cat > Dockerfile.i915-sriov <<'EOF'
FROM ghcr.io/siderolabs/tools:v1.12.1 AS tools
FROM ghcr.io/siderolabs/ca-certificates:v1.12.1 AS ca-certificates

FROM scratch AS base
COPY --from=tools / /
COPY --from=ca-certificates / /

# Build stage
FROM base AS build
WORKDIR /build
RUN apk add --no-cache \
    git \
    make \
    gcc \
    linux-headers

# Copy i915-sriov source
COPY i915-sriov-dkms/ /build/

# Build the module
RUN make -j$(nproc)

# Extension stage
FROM scratch
COPY --from=build /build/*.ko /lib/modules/
COPY --from=build /build/ /usr/local/src/i915-sriov/

# Metadata
LABEL org.opencontainers.image.source=https://github.com/strongtz/i915-sriov-dkms
LABEL org.talos.extension.name=i915-sriov
LABEL org.talos.extension.version=1.0.0
LABEL org.talos.extension.description="Intel i915 SR-IOV support for Talos Linux"
EOF

# Build the extension container
echo "Building extension container..."
docker build \
    -f Dockerfile.i915-sriov \
    -t localhost/i915-sriov:v${TALOS_VERSION} \
    ${BUILD_DIR}

# Export the extension
echo "Exporting extension..."
docker save localhost/i915-sriov:v${TALOS_VERSION} -o ${OUTPUT_DIR}/i915-sriov-${TALOS_VERSION}.tar

# Create extension manifest
cat > ${OUTPUT_DIR}/i915-sriov-extension.yaml <<EOF
---
apiVersion: v1alpha1
kind: ExtensionsServiceConfig
name: i915-sriov
environment:
  - i915.enable_guc=3

modules:
  - name: i915
    parameters:
      - enable_guc=3
EOF

echo ""
echo "=== Build Complete ==="
echo "Extension tarball: ${OUTPUT_DIR}/i915-sriov-${TALOS_VERSION}.tar"
echo "Extension manifest: ${OUTPUT_DIR}/i915-sriov-extension.yaml"
echo ""
echo "Next steps:"
echo "1. Copy the tarball to your image registry or local storage"
echo "2. Add to your Talos machine config:"
echo "   machine:"
echo "     install:"
echo "       extensions:"
echo "         - image: <your-registry>/i915-sriov:v${TALOS_VERSION}"
echo ""
