# ENG-14: kube-vip BGP anycast for cluster-101 apiserver VIP

## Goal

Replace the fragile Talos-native floating VIP behavior for
`fd00:101::10/128` with kube-vip BGP anycast, while leaving EVPN Type-5/L3VNI
deferred.

This branch implements the candidate config but does not remove the Talos VIP.
The Talos VIP should stay in place until the kube-vip route is proven from all
PVE nodes and normal kubeconfig access remains stable.

## Design

- kube-vip runs as a Talos `machine.pods` static pod on each control-plane node.
- kube-vip binds `fd00:101::10/128` to `lo` and runs BGP without leader
  election so all healthy control-plane nodes can advertise the same VIP.
- kube-vip peers only to the local Talos `bird2` extension, not directly to PVE.
- bird2 imports only `fd00:101::10/128` from kube-vip, tags it as
  `4200001000:0:200`, and exports it through the existing upstream session to
  PVE FRR.
- kube-vip uses the apiserver `/livez` health check with the Talos Kubernetes
  CA at `/etc/kubernetes/pki/ca.crt`; unhealthy local
  apiservers should withdraw their route.
- kube-vip is a static pod, so it does not get a service-account token; it
  mounts Talos' host kubelet kubeconfig from
  `/etc/kubernetes/kubeconfig-kubelet` at kube-vip's expected
  `/etc/kubernetes/admin.conf` path, also mounts the referenced kubelet client
  PEM at `/var/lib/kubelet/pki/kubelet-client-current.pem`, and talks to the
  local apiserver proxy at `https://127.0.0.1:7445`.
- PVE FRR policy gives the local CP next-hop a higher local-preference for this
  exact VIP and normalizes iBGP copies back to default preference.

## Expected next-hop selection

| PVE node | Preferred route for `fd00:101::10/128` |
| --- | --- |
| pve01 | `fd00:101::11` / solcp01 |
| pve02 | `fd00:101::12` / solcp02 |
| pve03 | `fd00:101::13` / solcp03 |

## Rollout

1. Review this branch.
2. Apply the Proxmox FRR template with the PVE Ansible path.
3. Render and review the Talos config:
   `cd terraform/infra/live/clusters/cluster-101/config && terragrunt plan`
4. Apply the Talos config through the normal apply unit:
   `cd terraform/infra/live/clusters/cluster-101/apply && terragrunt apply`
5. Watch static pod status:
   `talosctl --nodes fd00:101::11,fd00:101::12,fd00:101::13 get staticpodstatus`

## Validation

From each PVE node:

```bash
vtysh -c "show bgp vrf vrf_evpnz1 ipv6 unicast fd00:101::10/128"
vtysh -c "show ipv6 route vrf vrf_evpnz1 fd00:101::10/128"
ip vrf exec vrf_evpnz1 curl -g -k -sS -o /dev/null -w "%{http_code}\n" \
  https://[fd00:101::10]:6443/livez
```

From the workstation:

```bash
KUBECONFIG=/Users/sulibot/code/home-ops/talos/clusters/cluster-101/kubeconfig \
  kubectl get nodes -o wide
KUBECONFIG=/Users/sulibot/code/home-ops/talos/clusters/cluster-101/kubeconfig \
  kubectl get --raw=/readyz
```

Expected:

- all three control-plane nodes advertise the VIP while healthy;
- each PVE node selects its local CP next-hop;
- unauthenticated PVE curl reaches the apiserver and returns HTTP `401`;
- the normal kubeconfig endpoint `https://[fd00:101::10]:6443` works.

If authenticated `/readyz` fails but `/livez` and normal API calls work, treat
that as a control-plane/etcd readiness issue to investigate separately from the
BGP anycast route.

## Rollback

1. Set `kube_vip_bgp_anycast.enabled = false` in
   `terraform/infra/live/clusters/cluster-101/cluster.hcl`.
2. Re-apply the Talos config through the apply unit.
3. Re-apply the PVE FRR template without the ENG-14 local-pref policy if needed.
4. Confirm the cluster has returned to the existing Talos VIP behavior.

Do not disable the Talos-native VIP until the kube-vip path has passed the
validation above and a rollback window is clear.
