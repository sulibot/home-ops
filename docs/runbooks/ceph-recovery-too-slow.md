# Runbook: Ceph Recovery Is Too Slow

## Goal

Determine whether recovery is blocked by capacity, failed OSDs, disk latency, network issues, recovery throttles, or competing client IO.

## Immediate Checks

1. Confirm data safety:
   - Check degraded, undersized, stale, inactive, and remapped PGs.
   - Treat undersized or inactive PGs as page-level.
2. Confirm recovery progress:
   - Recovery/backfill bytes/s and objects/s.
   - Degraded/misplaced object count trend over 15-30 minutes.
3. Check blockers:
   - OSDs down/out.
   - Nearfull/backfillfull OSDs.
   - PGs stuck peering, backfill_wait, or backfilling.
4. Check contention:
   - Top RBD images by client IO.
   - Top VMs and pods using those images.
   - Backup jobs, databases, object storage compaction, or large restores.
5. Check slow devices:
   - OSD apply/commit latency.
   - Physical disk IO time and SMART/NVMe health.
   - Kernel ATA/NVMe errors.
6. Check network:
   - NIC errors, drops, retransmits.
   - Link speed and duplex.
   - Host-to-host packet loss if measured.

## Mitigation

- Pause or throttle backup jobs first.
- Reduce high-write workloads if impact allows.
- Tune recovery limits only after confirming client IO and hardware health.
- Replace or remove failed disks if recovery is blocked by bad media.

## Validate

- Recovery throughput increases.
- Degraded/misplaced object count decreases.
- Client latency remains acceptable.

## Useful PromQL

```promql
sum(rate(ceph_osd_recovery_bytes[5m]))
```

```promql
sum(rate(ceph_pool_wr_bytes[5m])) by (pool_name)
```

```promql
topk(10, ceph_osd_apply_latency_ms)
```

```promql
topk(10, rate(ceph_rbd_write_bytes_total[5m]))
```

