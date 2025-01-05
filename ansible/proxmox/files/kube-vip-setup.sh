#!/bin/bash

hextet_2=$(echo "$1" | cut -d ':' -f 2)
hextet_3=$(echo "$1" | cut -d ':' -f 4)
ansible_ip="$1"
VIP="fd00:${hextet_2}::10"
INTERFACE="eth0"
KVVERSION=$(curl -sL https://api.github.com/repos/kube-vip/kube-vip/releases | jq -r ".[0].name")

# Pull the kube-vip image
ctr image pull ghcr.io/kube-vip/kube-vip:${KVVERSION}

# Run the kube-vip manifest command directly within ctr run
ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:${KVVERSION} vip /kube-vip manifest pod \
  --interface $INTERFACE \
  --address $VIP \
  --controlplane \
  --arp \
  --leaderElection | tee /etc/kubernetes/manifests/kube-vip.yaml

sed -i '/hostPath:/!b;n;s|path: /etc/kubernetes/admin.conf|path: /etc/kubernetes/super-admin.conf|' /etc/kubernetes/manifests/kube-vip.yaml

# sed -i '/hostPath:/!b;n;s|path: /etc/kubernetes/super-admin.conf|path: /etc/kubernetes/admin.conf|' /etc/kubernetes/manifests/kube-vip.yaml
