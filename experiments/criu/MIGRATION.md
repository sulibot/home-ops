# CRIU migration gates

CRIU hibernation retains a Pod and saves its processes to node-local disk. It
replaces KEDA's **Pod deletion**, not merely `replicas: 0` with `replicas: 1`.
Keep each current KEDA route/scaler until its replacement passes the gates below.

## Current candidates

| App | Existing behavior | Before CRIU enrollment |
| --- | --- | --- |
| CloudBeaver | Always running; fresh-workspace CRIU pilot passed | Test database reconnection, SQL sessions, workspace locks, probes, and VPA interaction with the runtime |
| Collabora | HTTP KEDA, 30-minute idle | Validate an open document/WebSocket, save, idle, and reopen; never sleep during editing |
| OpenCloud | HTTP KEDA, 30-minute idle | Validate uploads, desktop sync, and background jobs, not only dashboard HTTP |
| OpenHands | HTTP KEDA, StatefulSet | Validate long agent jobs and worker/sandbox connections independently of browser traffic |
| Baserow | HTTP KEDA, 30-minute idle | Account for Celery, scheduled work, PostgreSQL, and Redis connections |
| Twenty server/worker | Two HTTP-driven KEDA targets | Separate request traffic from queue-worker activity; do not freeze the worker based solely on HTTP silence |
| Hermes | New deployment based on the supplied home-ops reference | Outbound chat polling and scheduled agent work need a wake path; dashboard-only hibernation is a safer first scope |

Zigbee/Z-Wave repository scalers follow controller availability, not user idleness
(not present among live ScaledObjects during this review). Notifier's explicit
zero replicas and Loki's disabled deployment modes are not HTTP scale-to-zero
candidates. Do not turn those on as a blanket zero-replica conversion.

## Per-app cutover

1. Validate the unmodified image on the opt-in runtime with disposable data.
2. Verify actual checkpoint success and process disappearance, memory reclamation,
   repeated network-triggered restore, preserved memory identity, and HTTP success.
   Successful HTTP alone can mask a cold restart.
3. Test PVC/file locks, external connections, active jobs, readiness/liveness,
   synthetic monitoring, node/pod replacement, and checkpoint disk cleanup.
4. Coordinate VPA and Zeropod in-place resource resizing. Freeing physical RAM does
   **not** free scheduler reservations unless requests are also resized. Do not
   allow two controllers to manage those requests concurrently.
5. In one reviewed GitOps change: retain one Pod, add `runtimeClassName: zeropod`
   and explicit eligible container/port annotations; remove its KEDA ScaledObject
   and InterceptorRoute; route ingress directly to the app Service. Observe before
   enrolling another application. Keep migration/capacity eviction disabled until
   independently validated.

Zeropod v0.13 falls back to killing/restarting after some checkpoint/restore
failures. This was observed in the synthetic canary when the Talos bootstrap
payload lacked gzip. That loses in-memory state: applications must tolerate a
normal restart, and checkpoint failures must be monitored before wider rollout.

Checkpoint files may contain credentials and application data. Keep them local
to the node, out of Git and the image registry; normal durable data still belongs
on backed-up persistent volumes. CRIU is not a backup or cross-node HA mechanism.
