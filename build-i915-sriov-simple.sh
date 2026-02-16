#!/bin/bash
set -euo pipefail

# Build i915-sriov kernel module for Talos 1.12.1 (kernel 6.18.2)
TALOS_VERSION="1.12.1"
KERNEL_VERSION="6.18.2"
BUILD_DIR="/root/talos-build"
OUTPUT_DIR="/root/talos-build/output"

echo "=== Building i915-sriov for Talos v${TALOS_VERSION} (kernel ${KERNEL_VERSION}) ==="

mkdir -p ${BUILD_DIR} ${OUTPUT_DIR}
cd ${BUILD_DIR}

# Clone i915-sriov-dkms if not already done
if [ ! -d "i915-sriov-dkms" ]; then
    echo "Cloning i915-sriov-dkms..."
    git clone https://github.com/strongtz/i915-sriov-dkms.git
fi

# Use Debian/Ubuntu with kernel headers to build
echo "Building kernel module using Debian build environment..."
cat > Dockerfile.build <<'DOCKERFILE'
FROM debian:trixie-slim

# Install build dependencies and kernel headers
RUN apt-get update && apt-get install -y \
    build-essential \
    linux-headers-6.18.2-talos \
    kmod \
    git \
    bc \
    rsync \
    wget \
    curl \
    || echo "Note: Exact kernel headers not available in repos, will try alternative..."

# If exact headers not available, download kernel source
RUN apt-get update && apt-get install -y \
    build-essential \
    linux-headers-amd64 \
    kmod \
    git \
    bc \
    rsync \
    wget \
    curl \
    flex \
    bison \
    libelf-dev \
    libssl-dev \
    dwarves \
    ca-certificates

WORKDIR /build

# Build will happen with source mounted
DOCKERFILE

docker build -t i915-build-env -f Dockerfile.build .

# Try building with available headers
echo "Attempting to build i915-sriov module..."
docker run --rm \
    -v ${BUILD_DIR}/i915-sriov-dkms:/build \
    -v ${OUTPUT_DIR}:/output \
    i915-build-env \
    bash -c '
        cd /build
        echo "Checking available kernel headers..."
        ls -la /usr/src/ || echo "No /usr/src found"
        ls -la /lib/modules/ || echo "No /lib/modules found"

        # Find available kernel headers
        KDIR=$(ls -d /usr/src/linux-headers-* 2>/dev/null | head -1)
        if [ -z "$KDIR" ]; then
            KDIR=$(ls -d /lib/modules/*/build 2>/dev/null | head -1)
        fi

        if [ -n "$KDIR" ]; then
            echo "Building against kernel headers: $KDIR"
            make KDIR=$KDIR -j$(nproc) || {
                echo "Build failed with standard method"
                exit 1
            }
            echo "Build successful!"
            cp -v *.ko /output/ 2>/dev/null || echo "No .ko files found"
        else
            echo "ERROR: No kernel headers found"
            exit 1
        fi
    '

if [ $? -eq 0 ] && [ -f "${OUTPUT_DIR}/i915.ko" ]; then
    echo ""
    echo "=== Build Successful ==="
    echo "Kernel module: ${OUTPUT_DIR}/i915.ko"
    echo ""
    echo "Note: This module is built against $(ls /usr/src/linux-headers-* 2>/dev/null | head -1 | xargs basename)"
    echo "Your Talos nodes are running kernel ${KERNEL_VERSION}-talos"
    echo ""
    echo "Next steps:"
    echo "1. Create a Talos system extension with this .ko file"
    echo "2. Or manually load it on Talos nodes (risky for production)"
else
    echo ""
    echo "=== Build Failed or Module Not Found ==="
    echo ""
    echo "The kernel module build did not produce the expected i915.ko file."
    echo "This is likely because:"
    echo "1. Talos uses a custom kernel (6.18.2-talos) not available in Debian repos"
    echo "2. Building kernel modules requires exact kernel version match"
    echo ""
    echo "Recommended alternative approaches:"
    echo "1. Use Talos Image Factory to build a custom image with i915-sriov"
    echo "2. Check if i915-sriov is already merged into mainline kernel 6.18+"
    echo "3. Create a proper Talos extension using the Talos PKGs build system"
fi
