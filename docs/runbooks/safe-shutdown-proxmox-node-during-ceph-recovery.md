# Runbook: Safe Shutdown of a Proxmox Node During Ceph Recovery

## Goal

Avoid worsening data safety while shutting down or maintaining a Proxmox host.

## Readiness Checks

1. Ceph health is acceptable:
   - No undersized, inactive, or stale PGs.
   - Recovery/backfill is complete or explicitly risk-accepted.
   - Remaining OSDs can maintain pool `min_size`.
2. Identify OSDs on the node and affected pools.
3. Confirm MON, MGR, and MDS quorum/rank placement.
4. Confirm Kubernetes workloads can move:
   - Check PodDisruptionBudgets.
   - Drain target Kubernetes nodes if needed.
5. Confirm Proxmox VM placement:
   - Migrate or shut down non-essential VMs.
   - Avoid live migration if Ceph is already saturated unless necessary.
6. Set maintenance labels and Alertmanager silences with expiry.

## Shutdown Order

1. Pause or drain application workloads if needed.
2. Drain affected Kubernetes nodes.
3. Shut down or migrate VMs.
4. Handle Ceph OSDs according to cluster policy.
5. Shut down the Proxmox host.

## Post-Startup Validation

- Remove silences.
- Verify OSDs are up/in.
- Verify PGs are clean.
- Verify workloads rescheduled and application latency is normal.

## Hard Stop Conditions

- Any undersized PGs.
- Nearfull or backfillfull OSDs.
- No standby MDS when host contains active MDS.
- MON quorum would be lost.
- Recent disk/NIC errors on remaining hosts.

