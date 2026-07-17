# Session handoff: ansible/lae.proxmox refactor + cluster-101 VIP fix (2026-07-14)

For pasting into a fresh session to pick up Linear updates or follow-up
work without re-deriving context. Both Linear tickets below were already
updated live during this session — this file is a backup/reference, not a
todo list for updating Linear again.

## ENG-9 — ansible/lae.proxmox refactor: DONE, committed

- Commit `e0dfcf2c` on `main`: "Refactor PVE ansible off lae.proxmox; fix
  TF/Ansible drift; retire redundant roles" (3528 files changed).
- **Not yet pushed to remote.**
- Full detail in the ENG-9 Linear issue description and
  `.claude/plans/declarative-forging-volcano.md`.
- Key structural change: `ansible/lae.proxmox/` -> `ansible/pve/` +
  `ansible/common/roles/` + `ansible/nat64/` + `ansible/_archive/`.
- Three roles retired as redundant with already-live Terraform
  (`pve_accounts`, `proxmox_oidc`, `vnet_gua` -> see
  `ansible/_archive/terraform-managed-redundant/README.md`).
- `perl_plugin` retired entirely by user preference (patched vendor Perl
  files, also found to target an older pve-network API) -> see
  `ansible/_archive/perl_plugin-retired/README.md`.
- Open follow-up: check for an active `.orig` backup of `perl_plugin`'s
  patched files on pve01-03 before permanently deleting the archive
  (vs. keeping it archived indefinitely).

## ENG-7 — cluster-101 kube-apiserver VIP: immediate symptom FIXED live, durable fix investigated and hit a real architectural wall (not solved)

- Symptom: `fd00:101::10` (kube-apiserver VIP) unreachable cross-fabric;
  cluster itself always healthy via direct node IPs.
- Root cause confirmed: Talos's VIP mechanism sends its gratuitous
  Neighbor Advertisement exactly once at claim time; Proxmox's EVPN
  ARP/ND suppression only learns via snooping that one packet, with no
  refresh mechanism. A missed or superseded NA leaves either no route or
  a stale one, permanently, until something re-triggers a fresh claim.
- **Fixed live 2026-07-14** by rebooting the VIP holder twice (first
  reboot bounced through a transient stale state on a second node before
  landing correctly on a third). Verified with the original failing
  command (`kubectl get po -A`) and a traceroute confirming the fix goes
  through the real EVPN fabric path, not a bypass. **This reboot is still
  the only reliable remediation** if this recurs.
- **Durable-fix investigation (three candidates, in order):**
  1. bird2 exporting the VIP via BGP the way it exports the LB pool —
     ruled out; the LB pool's reachability actually comes from Cilium's
     service mesh, not cross-node BGP propagation, so the comparison
     didn't hold for a plain Talos VIP with no service-mesh layer.
  2. A separate, real, already-working VRF-leak + iBGP mechanism (used
     today for pod CIDRs) — found the exact gap (`RM_GLOBAL_TO_VRF_V6`
     had no permit clause for tenant host routes tagged "Public"), added
     `route-map RM_GLOBAL_TO_VRF_V6 permit 35` live to all 3 PVE nodes
     and persisted it to `ansible/pve/roles/frr/templates/frr-pve.conf.j2`.
     Verified the route now reaches every node's `vrf_evpnz1` BGP table.
  3. **But it doesn't actually fix forwarding.** On non-originating
     nodes the route shows `Status: Failed` — a next-hop recursion
     problem. FRR's `import vrf` route-leak mechanism does not correctly
     resolve interface-based/link-local next-hops across VRF boundaries
     (confirmed as a documented FRR limitation via FRR's own GitHub
     issues). This is an architectural mismatch: an L3 VRF-leak
     mechanism can't substitute for the L2/EVPN Type-2 mechanism this
     address actually needs. Real cross-node forwarding still depends on
     EVPN Type-2 ARP/ND snooping succeeding, exactly as before this
     change.
  - The route-map addition is harmless (kept in place, has a full
    context comment at that entry) but is not a fix.
- **What would actually fix this (still open, not attempted):** EVPN
  Type-5/symmetric-IRB (the textbook-correct mechanism for this exact
  problem, but a real architecture change, previously ruled out as
  bigger than any single ticket's scope) or kube-vip in BGP mode
  replacing Talos's native VIP (untested whether it would dodge the same
  next-hop recursion wall). Absent either, the manual-reboot remediation
  is the standing runbook for this failure mode.

## Branch note

Mid-session, the checked-out branch had drifted to `otel-conversion`
(unrelated work — Linear/quiet-hours bridge config, 5 commits ahead of
where the ansible refactor started) without me switching it. Recovered by
stashing a stray uncommitted edit on that branch
(`otel-collector` helm chart version bump, unrelated to any of the above),
switching to `main`, committing there, then switching back to
`otel-conversion` and restoring the stash intact. Worth checking with the
user why the branch changed mid-session if it comes up again.
