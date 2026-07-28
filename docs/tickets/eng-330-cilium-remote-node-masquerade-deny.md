# Ticket: cluster-101 worker-to-worker pod traffic silently dropped by Cilium masquerade/remote-node policy bug

- Linear: ENG-330
- Status: Backlog
- Priority: High
- Area: cluster-101 networking, Cilium
- Created: 2026-07-28

## Summary

Discovered while investigating why Flux's `notification-controller` calls
were timing out cluster-wide (cascading `DependencyNotReady` across nearly
every Kustomization).

**Original hypothesis was an MTU black hole — that was wrong.** The real
cause: for pod-to-pod traffic between two different **worker** nodes,
Cilium masquerades the source IP to the sending node's own bare IP instead
of preserving the real pod IP, even though `ipv6NativeRoutingCIDR:
fd00:101::/48` is correctly configured everywhere. This causes the
destination node to classify the flow as the reserved `remote-node`
identity. Standard Kubernetes `NetworkPolicy` structurally cannot grant
access to `remote-node`/`host` reserved identities (`namespaceSelector: {}`
never matches them, since they carry no namespace label) — only
`CiliumNetworkPolicy` with `fromEntities: [remote-node]` can. Any namespace
with a restrictive standard NetworkPolicy (e.g. `flux-system`'s
`allow-scraping`) therefore silently denies all cross-worker-node pod
traffic to it.

Confirmed **universal across all 6 directional worker-node pairs** — not
pair-specific — and **not fixed** by the Cilium 1.19.1 → 1.19.6 upgrade
done this session (re-tested live post-upgrade, reproduces identically).

## Evidence

- `cilium-dbg bpf nat list` on all 3 worker agents, using `netshoot` debug
  pods pinned one-per-worker: every one of the 6 directional pairs shows
  `XLATE_SRC` rewriting the pod's source IP to the sending node's bare IP.
- `cilium-dbg monitor --type policy-verdict` on solwk01 while
  `nc -zv solwk02->source-controller:9090` timed out, captured live:
  ```
  Policy verdict log: flow 0x0 local EP ID 3130, remote ID remote-node, proto 6, ingress,
  action deny, auth: disabled, match none,
  [fd00:101::22]:58416 -> [fd00:101:224:3::9cac]:9090 tcp SYN
  ```
  Source is solwk02's bare node IP, not the real pod IP — proving the
  masquerade causes the misclassification. A bare TCP SYN is far too small
  for any MTU concern, ruling out PMTUD entirely.
- `cilium-health status` reporting 6/6 reachable is consistent with this
  root cause: ICMP health probes aren't subject to the same NetworkPolicy
  enforcement path, so they don't surface the bug.

## Why this matters

Silently breaks cross-worker-node pod traffic into any namespace with a
restrictive standard `NetworkPolicy`. Flux's `flux-system` namespace is the
visible symptom tonight; anything else with a similar policy shape is
likely affected too.

## Fix options (not yet implemented)

- Add `CiliumNetworkPolicy` with `fromEntities: [remote-node]` (or
  `cluster`) alongside/replacing the standard `NetworkPolicy` objects in
  namespaces that need to tolerate this — starting with `flux-system`.
- Root-cause why native routing mode masquerades intra-cluster traffic at
  all despite `ipv6NativeRoutingCIDR` being set (`enable-ipv6-masquerade` /
  `ipv6-native-routing-cidr` interaction) — possibly worth an upstream
  Cilium issue if it reproduces on a minimal repro.

## Acceptance criteria

- [x] Root cause confirmed (masquerade → remote-node identity → policy
      deny).
- [ ] Fix applied (CiliumNetworkPolicy allow-list, or masquerade
      root-cause fix).
- [ ] Worker-to-worker traffic into `flux-system` verified working
      end-to-end (re-run the original wget test from a Flux controller
      pod).
