#!/usr/bin/env bash
set -euo pipefail

# Script to reclaim Kopia repository PV after cluster rebuild
# This reads the subvolume ID from the secret stored in Git and creates the PV/PVC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRET_FILE="${REPO_ROOT}/kubernetes/apps/6-data/kopia/app/kopia-repository-subvolume-secret.yaml"

echo "=== Kopia Repository PV Reclaim Tool ==="
echo ""

# Check if secret file exists
if [[ ! -f "${SECRET_FILE}" ]]; then
    echo "ERROR: Secret file not found: ${SECRET_FILE}"
    exit 1
fi

# Extract values from the secret file
VOLUME_HANDLE=$(grep 'volumeHandle:' "${SECRET_FILE}" | awk '{print $2}' | tr -d '"')
CLUSTER_ID=$(grep 'clusterID:' "${SECRET_FILE}" | awk '{print $2}' | tr -d '"')
FS_NAME=$(grep 'fsName:' "${SECRET_FILE}" | awk '{print $2}' | tr -d '"')
STORAGE_CLASS=$(grep 'storageClass:' "${SECRET_FILE}" | awk '{print $2}' | tr -d '"')

echo "Read from Git:"
echo "  Volume Handle: ${VOLUME_HANDLE}"
echo "  Cluster ID:    ${CLUSTER_ID}"
echo "  FS Name:       ${FS_NAME}"
echo "  Storage Class: ${STORAGE_CLASS}"
echo ""

# Verify ceph-csi is deployed
if ! kubectl get storageclass "${STORAGE_CLASS}" &>/dev/null; then
    echo "ERROR: Storage class '${STORAGE_CLASS}' not found."
    echo "Make sure ceph-csi is deployed before running this script."
    exit 1
fi

# Check if PV already exists
if kubectl get pv kopia-repository-pv &>/dev/null; then
    echo "WARNING: PV 'kopia-repository-pv' already exists."
    read -p "Do you want to delete and recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete pv kopia-repository-pv
    else
        echo "Aborted."
        exit 0
    fi
fi

# Check if PVC already exists
if kubectl get pvc kopia -n default &>/dev/null; then
    echo "WARNING: PVC 'kopia' already exists in namespace 'default'."
    read -p "Do you want to delete and recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete pvc kopia -n default
    else
        echo "Aborted."
        exit 0
    fi
fi

echo ""
echo "Creating PersistentVolume..."

# Create PV manifest
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kopia-repository-pv
spec:
  capacity:
    storage: 200Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ${STORAGE_CLASS}
  csi:
    driver: cephfs.csi.ceph.com
    volumeHandle: ${VOLUME_HANDLE}
    volumeAttributes:
      clusterID: ${CLUSTER_ID}
      fsName: ${FS_NAME}
      storage.kubernetes.io/csiProvisionerIdentity: "cephfs.csi.ceph.com"
    nodeStageSecretRef:
      name: csi-ceph-admin-secret
      namespace: ceph-csi
EOF

echo "✓ PV created"
echo ""

# Wait for PV to be Available
echo "Waiting for PV to become Available..."
kubectl wait --for=jsonpath='{.status.phase}'=Available pv/kopia-repository-pv --timeout=30s

echo ""
echo "Creating PersistentVolumeClaim..."

# Create PVC manifest
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kopia
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ${STORAGE_CLASS}
  volumeName: kopia-repository-pv
  resources:
    requests:
      storage: 200Gi
EOF

echo "✓ PVC created"
echo ""

# Wait for PVC to be Bound
echo "Waiting for PVC to become Bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/kopia -n default --timeout=30s

echo ""
echo "=== Success! ==="
echo ""
echo "Kopia repository PV/PVC reclaimed successfully."
echo ""
echo "Next steps:"
echo "  1. Let Flux deploy the Kopia application"
echo "  2. Verify Kopia connects to repository:"
echo "       kubectl logs -n default -l app.kubernetes.io/name=kopia"
echo "  3. Check Volsync restores start working:"
echo "       kubectl get replicationdestination -n default -w"
echo ""
