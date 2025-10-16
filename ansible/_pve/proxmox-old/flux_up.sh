#!/bin/bash

kubectl label node " solcp011" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve01" --overwrite
kubectl label node " solcp012" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve02" --overwrite
kubectl label node " solcp013" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve03" --overwrite
kubectl label node " solcp014" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve01" --overwrite
kubectl label node " solcp015" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve02" --overwrite
kubectl label node " solcp016" node-role.kubernetes.io/worker=true topology.kubernetes.io/host="pve03" --overwrite

kubectl create ns flux-system

this key is on my local machine
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
--path=kubernetes/clusters/sol \
--interval=10m \
--timeout=5m