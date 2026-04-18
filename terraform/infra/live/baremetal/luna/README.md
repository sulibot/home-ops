# Luna Bare-Metal Talos

Single-node Talos Kubernetes cluster on repurposed bare-metal hardware.

- Cluster name: `luna`
- Node hostname: `luna01`
- Management network: `vlan10`
- Node IPs:
  - IPv4: `10.10.0.4`
  - IPv6: `fd00:10::4`

Workflow:

1. `secrets/` generates or reuses Talos machine secrets.
2. `config/` renders Talos config for `luna01` and exports repo-local artifacts.
3. `apply/` applies the machine config to a Talos node in maintenance mode.
4. `bootstrap/` bootstraps the one-node Kubernetes cluster and writes kubeconfig.
5. `cilium-bootstrap/` installs Gateway API CRDs and Cilium so the node can become Ready.

Notes:

- This stack does not provision compute. `luna01` is a physical machine.
- VIP is intentionally disabled. The node IP is the Kubernetes endpoint.
- Workloads are allowed on the control plane because this is a 1-node cluster.
