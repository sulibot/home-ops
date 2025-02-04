#!/bin/bash
kubectl label node "sol-worker-1" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve01" --overwrite
kubectl label node "sol-worker-2" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve02" --overwrite
kubectl label node "sol-worker-3" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve03" --overwrite
kubectl label node "sol-worker-4" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve01" --overwrite
kubectl label node "sol-worker-5" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve02" --overwrite

kubectl create ns flux-system

cat ~/.config/sops/age/age.agekey |
kubectl create secret generic sops-age \
--namespace=flux-system \
--from-file=age.agekey=/dev/stdin

flux bootstrap github \
--branch=main \
--personal \
--private \
--token-auth \
--owner=sulibot \
--repository=home-ops \
--path=kubernetes/clusters/production \
--interval=10m \
--timeout=5m