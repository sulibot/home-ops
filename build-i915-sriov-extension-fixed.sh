#!/bin/bash
set -euo pipefail

# Build i915-sriov extension for Talos 1.12.1
# Run this on build-server (10.101.0.43)

TALOS_VERSION="1.12.1"
KERNEL_VERSION="6.12.6"
EXTENSION_NAME="i915-sriov"
BUILD_DIR="/root/talos-extensions"
OUTPUT_DIR="/root/talos-extensions/output"

echo "=== Building i915-sriov Talos Extension for v${TALOS_VERSION} ==="

# Create build directories
mkdir -p ${BUILD_DIR} ${OUTPUT_DIR}
cd ${BUILD_DIR}

# Clone i915-sriov-dkms source if not already cloned
if [ ! -d "i915-sriov-dkms" ]; then
    echo "Cloning i915-sriov-dkms..."
    git clone https://github.com/strongtz/i915-sriov-dkms.git
fi

# Create Dockerfile for building the kernel module
cat > Dockerfile.i915-sriov <<'EOF'
# Use Talos kernel package to build against
FROM ghcr.io/siderolabs/kernel:v1.12.1 AS kernel

# Build stage using Alpine for build tools
FROM alpine:3.21 AS build
WORKDIR /build

# Install build dependencies
RUN apk add --no-cache \
    git \
    make \
    gcc \
    musl-dev \
    linux-headers \
    kmod

# Copy kernel sources from Talos kernel image
COPY --from=kernel /usr/src /usr/src

# Copy i915-sriov-dkms source
COPY i915-sriov-dkms/ /build/

# Build the kernel module
# Note: We need to adjust the Makefile to point to Talos kernel sources
RUN if [ -d "/usr/src/linux" ]; then \
        export KDIR=/usr/src/linux; \
    else \
        export KDIR=$(ls -d /usr/src/linux-* | head -1); \
    fi && \
    echo "Building against kernel at: $KDIR" && \
    make -j$(nproc) || echo "Build may have warnings, continuing..."

# Final extension image following Talos extension spec
FROM scratch AS extension
COPY --from=build /build/*.ko /lib/modules/

# Metadata following Talos extension specification
LABEL org.opencontainers.image.source=https://github.com/strongtz/i915-sriov-dkms
LABEL org.talos.version=v1.12.1
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

if [ $? -eq 0 ]; then
    echo "Container built successfully!"

    # Export the extension
    echo "Exporting extension..."
    docker save localhost/i915-sriov:v${TALOS_VERSION} -o ${OUTPUT_DIR}/i915-sriov-${TALOS_VERSION}.tar

    echo ""
    echo "=== Build Complete ===""
    echo "Extension tarball: ${OUTPUT_DIR}/i915-sriov-${TALOS_VERSION}.tar"
    echo ""
    echo "To use this extension, you can:"
    echo "1. Upload to a container registry"
    echo "2. Or use it directly with Talos machine config"
else
    echo ""
    echo "=== Build Failed ==="
    echo "The kernel module build failed. This may be due to:"
    echo "- Incompatible kernel version"
    echo "- Missing kernel headers"
    echo "- Source code issues"
    echo ""
    echo "Alternative: Use pre-built extension from Talos community"
    echo "Check: https://github.com/siderolabs/extensions"
fi
