# Alerting and automatic remediation backlog

This backlog captures cross-layer failure modes that should remain observable
after individual incidents are closed. Automatic remediation must stop when its
safety preconditions cannot be proved.

## Kubernetes control plane

- Alert when a node's kubelet repeatedly fails calls to `127.0.0.1:7445`
  (KubePrism), even if the Talos kubelet service reports healthy.
- Correlate node lease age, KubePrism failures, hypervisor, and control-plane
  endpoint readiness. A host-level correlation should fire when two guests on
  the same PVE node fail together.
- Remediation: rebuild host FRR only when its kernel nexthop installation has
  failed. Reset an already-NotReady worker first. Reset a control-plane guest
  only after two other etcd members pass readiness and quorum checks.
- Alert on the Kubernetes API VIP separately from the three direct API
  endpoints so an unhealthy VIP path is not confused with etcd failure.
- Alert when a Proxmox HA watchdog reboot correlates with loss of the routed
  quorum path. Router maintenance must account for the shared failure domain;
  automatic router reboot is unsafe unless guest fencing is inhibited or an
  independent Corosync path is proved healthy.
- Remediation after an abrupt multi-node restart: replace only controller-owned
  pods that remain `Running` with no pod IP and terminated containers in
  `Unknown`. Rate-limit deletes to avoid loading etcd during recovery.
- Correlate full-revision Flux reconciliation with controller filesystem write
  rate, node XFS workqueue count, load per core, and I/O PSI. On 2026-08-25,
  `kustomize-controller --concurrent=20 --requeue-dependency=5s` drove the
  Ceph-backed Talos system disk above load 1,100; four workers and 30-second
  dependency retries kept the same revision wave below the saturation point.
- Remediation: when the kustomize-controller is the proven write source and
  full I/O PSI is severe, scale only that controller to zero, let the host
  drain, then restore it with bounded concurrency. Do not restart the worker or
  fan out forced reconciliations while storage-backed kernel work is blocked.

## Ceph and persistent volumes

- Alert on application log signatures containing `Input/output error` beneath
  known PVC mount paths, not only CSI pod health.
- Correlate stale mounts with node state, CSI restarts, RBD attachment state,
  CephFS sessions, and BlueStore slow-op timestamps.
- Remediation: replace an already-failed application pod to force a clean
  remount. For a single-instance database, require a successful volume detach
  before rescheduling and verify database crash recovery before restarting
  dependents.
- Keep the CephFS/RBD mount-doctor jobs. Alert on their latest result, while
  excluding retained historical failed Jobs after a newer run succeeds.
- Alert on CephFS MDS cache usage, inode/dentry count, request rate, client-cap
  count, and host memory together. `MDS_CACHE_OVERSIZED` plus rising cache and
  BlueStore slow ops is an active metadata incident, not a warning to mute.
- Correlate recursive `VolumePermissionChangeInProgress` events with MDS cache
  growth. Require `fsGroupChangePolicy: OnRootMismatch` on VolSync movers and
  alert when the rendered ReplicationSource has drifted from that setting.
- Remediation: pause only affected ReplicationSources and cancel stuck kubelet
  ownership walks before touching an MDS. Do not force MDS failover when Ceph
  rejects it for `MDS_CACHE_OVERSIZED` or `MDS_TRIM`; require an operator to
  accept the explicit filesystem-availability risk.
- Alert on cluster-wide active scrub and deep-scrub PG counts, not only
  `osd_max_scrubs`. That setting limits each OSD independently: clearing the
  scrub flags on 2026-08-25 immediately started eight simultaneous PG scrubs
  and drove a colocated Kubernetes worker above load 500 even with
  `high_client_ops` and `osd_max_scrubs=1`.
- Remediation may automatically set `noscrub` and `nodeep-scrub` when multiple
  active scrubs correlate with severe worker I/O PSI or control-plane errors.
  Automatically clearing those flags is unsafe; resume scrubbing only in a
  monitored maintenance window with an explicit cluster-wide concurrency or
  scheduling control and a rollback threshold.

## Applications and backups

- Plex: probe the internal service, public TLS endpoint, Plex.tv presence,
  advertised connection URIs, and stable friendly name. Do not restart while
  active sessions exist unless the config mount is already failed.
- PostgreSQL/Valkey: alert on the primary service having no ready endpoint and
  correlate dependent application failures to avoid paging once per client.
- VolSync: alert on cache filesystem utilization and quota headroom before the
  mover fails. The cache limit must leave room for Kopia config and logs.
- Alert separately when a VolSync mover reports cache corruption together with
  files in `own-writes`. Treat this as interrupted repository work: quarantine
  and inspect the cache before retrying. Never automatically delete the cache
  while uncommitted writes are present.
- Do not count Kopia's `.shards` bookkeeping file as an uncommitted write. The
  cache-recovery guard must distinguish it from actual pending pack data.
- Alert when a deleted VolSync pod leaves a Kopia process behind on its node.
  Correlate Kubernetes pod UID, CRI task, and host PID; terminate only the
  proven orphan instead of restarting containerd and every workload on a node.
- Remediation must never recursively delete a large Kopia cache in one pass on
  CephFS. Quarantine only regenerable index data, preserve `own-writes`, stop if
  MDS/OSD latency rises, and remove quarantined entries in rate-limited batches.
- Remediation: expand an expandable cache PVC within an application-specific
  ceiling, then verify a successful new snapshot. Never initialize a new Kopia
  repository merely because connecting to an existing repository failed.
- Home Assistant config backup: alert on snapshot fatal errors as well as
  CronJob freshness. The read-only backup needs `DAC_READ_SEARCH` after
  dropping all other capabilities so mode-0700 recovery state is included.
- Alert when a Kopia repository exceeds a safe index-blob count and run
  repository maintenance under a singleton lock; do not run maintenance from
  every backup Job.

## Physical and routed network

- Track errors, drops, and misses separately by host, parent device, VLAN,
  direction, packet type, and rate. Correlate a bond with its active slave so a
  single physical counter does not create duplicate incidents.
- Distinguish `rx_missed_errors` (NIC/ring pressure) from Linux `rx_dropped`,
  multicast floods, CRC/carrier faults, and transmit drops.
- Remediation: for a known single-queue NIC with a ring already at its hardware
  maximum, enable host-specific RPS/RFS and remeasure. Do not apply generic NIC
  tuning cluster-wide.
- RouterOS: independently probe ICMP reachability, REST authentication, and
  SNMP response. A reachable router with REST 401 or SNMP timeout requires a
  router credential/service-policy fix, not a Kubernetes pod restart.
- Alert on RouterOS CPU and REST active-session count/rate. ExternalDNS should
  reconcile no faster than once per minute; a rapidly growing REST session
  count indicates a client or RouterOS connection-lifecycle defect.
- SNMP requires a return route for the exporter pod CIDR when the request keeps
  its pod source address on the secondary VLAN. Verify request and response
  directions with a packet capture before changing firewall or community ACLs.
- Manage that pod-CIDR return route declaratively in RouterOS infrastructure as
  code (or replace it with routed pod-CIDR advertisement), and alert when the
  route is absent or points at an unavailable next hop.
- Correlate router forwarding load with Ceph client/recovery I/O. High unicast
  rates between PVE ports are not a Sonos/multicast flood; alert separately on
  multicast packet rate and unknown-multicast replication.

## NFS gateway

- Alert when either gateway lacks its explicit `fc00:20::/64` Ceph messenger
  route, before Ganesha recovery initialization times out.
- The route unit must retry after boot because `network-online.target` can be
  reached before the LXC receives its IPv6 address.
- Remediation: only after Ceph is healthy, restore both explicit routes and run
  the repository-owned HA reconciliation. Prove exactly one dual-stack VIP
  owner, one Ganesha listener, both exports, and an end-to-end NFS write.

## Home Assistant and physical devices

- Keep backup freshness, integration availability, Matter node reachability,
  music target availability, and automation execution health separate.
- Remediation may reload an integration or restart a failed software service.
  Do not power-cycle or remove a Matter device automatically; require physical
  reachability evidence and preserve commissioning state.
