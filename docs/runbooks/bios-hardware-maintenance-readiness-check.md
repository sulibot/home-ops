# Runbook: BIOS/Hardware Maintenance Readiness Check

## Goal

Decide whether firmware or hardware maintenance is safe and likely relevant to repeated node, disk, NIC, or Ceph behavior.

## Checks

1. Inventory:
   - Board model.
   - BIOS version.
   - NIC model, firmware, driver, and PCIe slot.
   - Disk model, firmware, serial, bus, and slot.
2. Error history:
   - PCIe AER.
   - MCE.
   - EDAC.
   - ATA resets.
   - NVMe timeouts.
   - NIC link flaps, drops, and errors.
3. Pattern analysis:
   - Same host repeatedly affected?
   - Same physical slot or cable?
   - Same board/BIOS version across affected nodes?
   - Same NIC or disk model?
4. Cluster safety:
   - Ceph clean.
   - Kubernetes workloads healthy.
   - Backups recent.
   - Proxmox VMs migratable or safely stoppable.
5. Maintenance plan:
   - One host at a time.
   - Document pre-change firmware state.
   - Capture config backups.
   - Define rollback or replacement plan.
6. Post-change validation:
   - OSDs up/in and PGs clean.
   - NIC speed/duplex correct.
   - No new kernel hardware errors.
   - Workload latency normal.

