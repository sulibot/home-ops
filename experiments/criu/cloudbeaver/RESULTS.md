# Native Talos result: CloudBeaver pilot

The disposable pilot namespace and its empty workspace/checkpoints were removed
after the test. Production CloudBeaver was not modified.

Tested on `solwk03` with Talos 1.14.1, containerd 2.3.5, CloudBeaver 26.1.1,
CRIU 4.2.1, and image
`zot.sulibot.com/experiments/criu-cloudbeaver@sha256:3859b5bd3cbce2f12c84eaf5bbb1ab20e876609f26d2c829c62cd1d7cdf00998`.
`test_cycle.py` exited 0 after a manual and then an automatic idle checkpoint,
each restored by an actual HTTP `GET /` through the supervisor. Both responses
were HTTP 200, 6,725 bytes. The restored Java process kept PID 7 and the same
random, memory-only pilot identity across both cycles.

| Observation | First cycle | Second cycle |
| --- | ---: | ---: |
| `memory.current` before sleep | 231,698,432 B | 232,095,744 B |
| `memory.current` asleep | 12,783,616 B | 12,865,536 B |
| `memory.current` reclaimed | 218,914,816 B | 219,230,208 B |
| Checkpoint archive | 217,096,878 B | 219,045,475 B |
| Dump time | 1,429 ms | Not recorded |
| Full wake-and-HTTP response | 1,078 ms | 924 ms |

After the first restore, `memory.current` was 232,095,744 B; after the second,
233,963,520 B. CRIU's cycle-2 logs reported both dump and restore successful.
These are two observations on one disposable Pod, not latency or reliability
benchmarks. The 512 MiB scheduler memory request did **not** decrease while the
JVM was asleep; this demonstrates physical memory reclamation, not capacity
rescheduling.

The initial dump exposed two requirements for this non-root JVM: `SYS_RESOURCE`
for CRIU's cross-UID resource-limit read, then `--file-locks` on both dump and
restore for Java/Equinox/H2 locks. The tested Pod is still highly privileged:
six added capabilities and unconfined seccomp. See [CRIU file-lock guidance](https://criu.org/File_locks)
for the requirement that all lock users be included in a dump.

This test used a fresh, empty workspace with no production PVC, database
credentials, external database connection, authenticated session, WebSocket,
file upload, or concurrent traffic. It does **not** establish safe restoration
of any of those states or justify changing the production CloudBeaver Deployment.
The checkpoint resides on disk-backed `emptyDir` and disappears with its Pod.
