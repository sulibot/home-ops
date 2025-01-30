#!/bin/bash
set -e

echo "Current Node: $(hostname)"
echo "Proxmox Host: $(cat /etc/proxmox-hostname)"
echo "Kubernetes API URL: https://kubernetes.default.svc"

TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
echo "Token loaded successfully."

# Execute the API request
curl -v -X PATCH \
  --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json-patch+json" \
  -d '[{"op": "add", "path": "/metadata/labels/ceph-host", "value": "'"$(cat /etc/proxmox-hostname)"'"}]' \
  https://kubernetes.default.svc/api/v1/nodes/$(hostname)
