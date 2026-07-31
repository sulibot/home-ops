# Runbook: Ceph MDS Crash

## Goal

Restore CephFS metadata availability and identify whether the crash was caused by daemon failure, metadata pressure, client behavior, or underlying pool/OSD issues.

## Steps

1. Check active and standby MDS ranks.
2. Confirm whether CephFS clients are blocked.
3. Inspect MDS logs around the crash.
4. Check MDS memory, cache pressure, and request latency.
5. Check metadata pool health and OSD latency.
6. Identify heavy CephFS clients and paths if instrumentation supports it.

## Mitigation

- Ensure a standby MDS is available.
- Restart the failed MDS if it is not flapping.
- Pause metadata-heavy jobs if MDS pressure is high.
- Preserve crash dumps and logs for repeated crashes.

## Escalate When

- More than two MDS crashes occur in 30 minutes.
- No standby MDS is available.
- CephFS clients are blocked.
- Metadata pool health is degraded or undersized.

## Related: MDS cache oversizing causing host memory exhaustion (not a crash)

`mds_cache_memory_limit` is a soft target, not a hard cap - under heavy
client churn (e.g. a mass CephFS reconnect storm after an unrelated
incident), the MDS can legitimately exceed it by 2x or more while trimming
catches up. This doesn't crash the MDS itself, but on a memory-constrained
PVE host it can starve everything else running there and trigger a kernel
OOM-kill of an unrelated VM. Confirmed live 2026-07-31 (ENG-364): `ceph
daemon mds.<id> cache status` showed ~2x the configured limit on both
pve01 and pve02 during a mass-reconnect event; `systemctl restart
ceph-mds@<id>` (safe with a standby available) immediately reclaimed the
memory. `ceph -s` reporting "N MDSs report oversized cache" is the health
warning to watch for - it's a distinct signal from an actual crash and
doesn't require a standby failover to resolve, just a plain restart.

pve01/pve02 also now carry a dedicated 128GB Optane-backed swap partition
(`ansible/pve/roles/optane_swap/`) specifically as a cushion against this
class of host memory pressure - see ENG-364 for the full incident writeup.
pve03 does not have this (its Optane module is much smaller and already
fully allocated) and separately has an open, unresolved recurring-crash
investigation of its own (ENG-365, HA-watchdog self-fence reboots) - if
pve03 shows MDS or memory pressure symptoms, treat it with extra caution
given that history.

