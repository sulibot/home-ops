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

