#!/bin/bash

hextet_2=$(echo "$1" | cut -d ':' -f 2)
hextet_3=$(echo "$1" | cut -d ':' -f 4)
ansible_ip="$1"
VIP="fd00:${hextet_2}::10"
INTERFACE="lo"
KVVERSION=$(curl -sL https://api.github.com/repos/kube-vip/kube-vip/releases | jq -r ".[0].name")

# Pull the kube-vip image
ctr image pull ghcr.io/kube-vip/kube-vip:${KVVERSION}

# Run the kube-vip manifest command directly within ctr run
ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:${KVVERSION} vip /kube-vip manifest pod \
  --interface $INTERFACE \
  --address $VIP \
  --controlplane \
  --bgp \
  --localAS 65${hextet_2} \
  --bgpRouterID 10.0.${hextet_2}.${hextet_3} \
  --bgppeers [fd00:${hextet_2}::1]:65000::false | tee /etc/kubernetes/manifests/kube-vip.yaml
