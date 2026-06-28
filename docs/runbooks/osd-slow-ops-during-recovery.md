# Runbook: OSD Slow Ops During Recovery

## Goal

Determine whether slow ops are expected recovery contention or a client, disk, network, host, or hardware fault.

## Steps

1. Identify which OSDs report slow ops.
2. Check if those OSDs are recovery targets or sources.
3. Compare client IO and recovery IO.
4. Check OSD apply and commit latency trends.
5. Check physical disk health and kernel errors for the OSD device.
6. Check NIC errors, drops, retransmits, link speed, and duplex.
7. Check Proxmox host CPU, memory, disk, and network pressure.

## Classification

| Classification | Evidence | Mitigation |
|---|---|---|
| Client load | Hot RBD images, high VM/pod IO, low recovery load | Pause or throttle top workload |
| Recovery load | High recovery IO, many PGs backfilling, moderate client IO | Tune recovery/client balance |
| Disk latency/fault | One OSD/device outlier, SMART/NVMe/SATA errors | Replace, mark out, or repair disk path if safe |
| Network issue | Multiple OSDs on same host slow plus NIC errors | Fix link, cable, switch, driver, or route |
| Host pressure | CPU, memory, or IO pressure on one Proxmox host | Migrate non-storage VMs if safe |

