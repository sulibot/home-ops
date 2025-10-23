#!/bin/bash
# Manual script to update onepassword secret correctly

set -e

cd "$(dirname "$0")"

echo "Fetching credentials from 1Password..."
TOKEN=$(sops -d secrets/1password-token.sops.yaml | sed 's/op_service_account_token: //')
echo "Encoding credentials as base64..."
CREDS=$(OP_SERVICE_ACCOUNT_TOKEN="$TOKEN" op read "op://Kubernetes/1password-connect/credentials" | base64)
TOKEN_VAL=$(OP_SERVICE_ACCOUNT_TOKEN="$TOKEN" op read "op://Kubernetes/1password-connect/token")

echo "Creating secret..."
kubectl create secret generic onepassword-secret -n external-secrets \
  --from-literal=1password-credentials.json="$CREDS" \
  --from-literal=token="$TOKEN_VAL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Restarting onepassword pods..."
kubectl delete pod -n external-secrets -l app.kubernetes.io/name=onepassword

echo "Done!"
