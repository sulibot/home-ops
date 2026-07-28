# Ticket: cluster-101 worker-to-worker pod traffic silently drops above a certain packet size

- Status: Todo
- Priority: High
- Area: cluster-101 networking, Cilium, EVPN fabric
- Created: 2026-07-28

## Summary

Discovered while investigating why Flux's `notification-controller` calls
were timing out cluster-wide (cascading `DependencyNotReady` across nearly
every Kustomization). Root cause is **not** Flux, and not the
`tier-0-foundation` cascade documented in
`project_cluster_flux_tier0_stuck` memory (different symptom, that one was
IPv6 egress via CoreDNS; this one is worker-to-worker pod traffic).

Real HTTP/TCP traffic between pods on different **worker** nodes
(`solwk01`/`solwk02`/`solwk03`) hangs and times out. The same request
between a worker and a **control-plane** node succeeds fine. Small packets
(Cilium's own ICMP-based health probes, DNS UDP queries) succeed on every
path, including worker-to-worker — only larger TCP payloads (HTTP
responses) hang. This is the textbook signature of an MTU black hole: path
MTU discovery isn't working, so packets above some threshold get silently
dropped somewhere in the fabric instead of getting an ICMP
"fragmentation needed" back.

## Evidence

- `kubectl exec -n flux-system deploy/kustomize-controller -- wget ... http://notification-controller...` (solwk01 → solwk03): **times out**.
- Same test solwk01 → solwk02: **times out**.
- Same test solwk01 → solcp01 (CoreDNS metrics endpoint): **succeeds**, full response.
- `cilium-health status` (ICMP-based probe): **6/6 reachable**, including solwk02/solwk03 — contradicts the real-traffic result above.
- `cilium-dbg status --verbose`: MTU consistently 1450 on both solwk01 and solwk03's `ens18`, `packetization-layer-pmtud-mode: blackhole` already configured (Cilium's own PLPMTUD blackhole-detection mitigation, already enabled but apparently not fully compensating).

## Why this matters

This is silently breaking any pod-to-pod communication between worker
nodes that involves a real payload of any size — Flux's notification
events are just the visible symptom (they're the thing that logs loudly on
failure). Anything else doing cross-worker-node pod traffic (most
in-cluster service calls that aren't small) is likely affected too.

## Suspected relationship to prior fabric work

Likely the same underlying EVPN/FRR fabric as
`docs/tickets/pve-frr-power-event-20260712.md` (documented MTU/hairpin
issues on the same fabric) and
`docs/tickets/pve-evpn-vip-arp-nd-suppression-gap.md`, but this specific
worker-to-worker packet-size-dependent symptom hasn't been characterized
before. Not fixed in this session — no direct Proxmox/FRR host access from
here, and blindly changing live EVPN/MTU config on production network
fabric without being able to verify the fix is exactly the kind of action
that needs deliberate, in-person investigation rather than a
kubectl-only session.

## Suggested next steps

- From a PVE host or a debug pod with raw ping, test `ping -M do -s <size>`
  at increasing sizes between solwk01/02/03 directly (bypassing Cilium) to
  find the actual black-holed size and isolate whether it's Cilium's
  VXLAN/Geneve encap, the EVPN overlay, or the underlay mesh.
- Compare worker vs control-plane node network config (VM NIC MTU, vNIC
  type, whichever Proxmox bridge/VNet each is attached to) for a
  difference that only affects workers.
- Check `pve-frr-power-event-20260712.md`'s vmbr0.10 loop / hairpin notes
  for a plausible connection.

## Acceptance criteria

- [ ] Black-holed packet size range identified.
- [ ] Root cause isolated to a specific fabric layer (Cilium encap vs EVPN
      overlay vs underlay).
- [ ] Fix applied and worker-to-worker large-payload traffic verified
      working (re-run the wget test above from a Flux controller pod).
