# Native Talos CRIU experiment — 2026-09-28

Target: `solwk03`, Talos v1.14.1, Kubernetes v1.37.0, containerd 2.3.5,
kernel 6.18.51-talos, amd64. Only the disposable `criu-experiment` namespace
was used. No runtime handler, machine configuration, or existing app changed.

## Final HTTP idle/wake test: passed with CRIU 4.2.1

Image: `zot.sulibot.com/experiments/criu@sha256:e541435075d9de5154df4f327efd508cd33fb1c4f1a301064e994edbc76c0fd3`

The child now runs an actual HTTP listener on localhost:8081. The supervisor
wakes it on `/request` and forwards the request. It automatically checkpoints
after 30 seconds without application requests; polling `/status` does not wake
it. Both a manually triggered and an automatically triggered sleep cycle passed.

| Metric | Manual cycle | Automatic cycle |
|---|---:|---:|
| Running container `memory.current` | 157,913,088 B | 158,162,944 B |
| Sleeping container `memory.current` | 13,307,904 B | 13,074,432 B |
| Total charged memory freed | 144,605,184 B | 145,088,512 B |
| CRIU restore + checkpoint cache eviction | 500 ms | 410 ms |
| Complete client wake request over port-forward | 516 ms | 426 ms |

The first checkpoint took 1,245 ms including fsync/cache eviction. Archive size
was approximately 144 MB (137.5 MiB). The memory-only random identity was
identical before and after both restores; the counter continued from 0 to 2 to
33, and the child retained PID 7. Restored file cache returned to 4,096 bytes
after targeted eviction, avoiding the double-memory effect seen with poc2.

This demonstrates roughly **151 MiB running → 12.5 MiB sleeping**, with a
**0.43–0.52 second first request** in these two measured cycles. These are
synthetic-workload measurements, not performance promises for existing apps.
The archive is still ephemeral, privileges are still broad, and Kubernetes
requests are not resized. No real app has been migrated to this mechanism.

Historical stages and compatibility discoveries follow.

### Final capability-only HTTP profile: also passed

The same CRIU 4.2.1 image passed both HTTP cycles with `privileged: false`, the
five capabilities listed below, and unconfined seccomp. This is now the default
security profile in `pod.yaml`; the separately named `pod-capabilities.yaml`
records the parallel comparison test. It is not a restricted-security profile.

- Baseline charged memory: 157,470,720 bytes.
- Manual sleep: 13,107,200 bytes; automatic sleep: 12,886,016 bytes.
- Full client wake request: **584 ms** manual, **726 ms** automatic.
- CRIU restore plus cache eviction: 567 ms and 707 ms, respectively.
- Manual dump plus fsync/eviction: 2,085 ms.
- Same memory-only identity, counter 0 → 2 → 33, and PID 7 across both cycles.

Both temporary Pods and their test-only namespace were removed after validation.
Their synthetic checkpoint data is intentionally not retained; the source,
digest-pinned registry image, manifests, and repeatable test remain available.

## Manual same-Pod cycle: passed

Image: `zot.sulibot.com/experiments/criu@sha256:7150cd6bd8a40aee583097f601479aa74576c561719602a50cfeed5b8a664b24`

CRIU 4.1.1 `criu check` and `criu check --all` returned `Looks good.` on the native worker.
The synthetic child allocated and touched 128 MiB. Its Python counter was
initialized only at process startup, then preserved by CRIU.

| Metric | Running | Checkpointed | Restored |
|---|---:|---:|---:|
| Container cgroup `memory.current` | 148,754,432 B | 11,153,408 B | 286,154,752 B |
| Container cgroup anonymous memory | 147,234,816 B | 10,182,656 B | 147,271,680 B |
| Container cgroup file cache | 4,096 B | 4,096 B | 137,179,136 B |
| Child RSS | 139,548 KiB | absent | 135,580 KiB |
| Child PID | 7 | absent | 7 |
| Counter | 2 | 2 (stopped) | 3 (advancing) |

- Checkpoint plus file fsync/cache-eviction advice: **1,485 ms**.
- Restore command: **317 ms**; not an end-to-end user-request measurement.
- Checkpoint files: **137,180,017 bytes** before restore logs.
- Total charged memory released: **137,601,024 bytes (131.23 MiB; 92.5%)**.
- Sleeping footprint: **10.64 MiB**, plus Pod sandbox/runtime overhead outside
  this container cgroup. Kubernetes memory requests remained 256 MiB: freeing
  actual RAM does not automatically free scheduler reservations.

After restore, image pages were again present in the file cache; a follow-up
version must advise eviction after restore as well. Cache eviction used
`fsync` and `POSIX_FADV_DONTNEED` on this test's checkpoint files only, never
host-wide `drop_caches`.

Limitations: privileged synthetic Pod, same Pod/node only, disk-backed emptyDir
(checkpoint lost when Pod is deleted), no real application/database validation.
This proves the mechanism, not generic application or production readiness.

## Reproducibility lessons

- `--verbosity=4` is accepted; `--verbosity 4` is not accepted by this CRIU CLI.
- A privileged Pod sees the host cgroup filesystem. Resolve its own cgroup
  from `/proc/self/cgroup`; measuring the filesystem root gives host totals.
- Reap the dumped child before restoring its PID.
- Native amd64 testing is necessary: local Rosetta emulation rejects CRIU's
  clone flags, even though the same image works on the Talos worker.
- Wait for deletion to complete before recreating the same test Pod; a normal
  30-second termination grace can exceed a 30-second kubectl wait deadline.

## Capability-only variant: passed for the synthetic process

`pod-capabilities.yaml` uses `privileged: false`, unconfined seccomp, default
container capabilities plus `CHECKPOINT_RESTORE`, `SYS_PTRACE`, `SYS_ADMIN`,
`NET_ADMIN` and `SYS_TIME`. This is narrower than fully privileged, but still
powerful and **not** a restricted-security workload or a proven minimal set.

With the same poc2 image, the full test passed: `memory.current` fell from
148,865,024 to 11,329,536 bytes; checkpoint took 1,359 ms; restore took 461 ms;
the counter advanced from 9 to 10 after restore. Without `SYS_TIME`, restore
failed setting the monotonic clock offset. Removing `SYS_ADMIN` caused CRIU's
kernel feature initialization to fail creating a network namespace. No attempt
was made to weaken node-wide security or change the host clock.

## HTTP listener: CRIU 4.1.1 is insufficient

The first HTTP-child test (`poc3`, image index
`sha256:452936964731c37f98c28c65ec85a869913f672f618c54eb1f4ea6c155cf3964`)
failed during dump, despite `criu check --all` passing for this installation.
The actual TCP listener exposed a kernel/userspace compatibility problem:

```text
sockets: Can't get 1:16 opt: Operation not supported
sockets: Can't get 1:34 opt: Operation not supported
Dump files (pid: 7) failed with -1
```

These are `SO_PASSCRED` and `SO_PASSSEC`. In upstream CRIU 4.2.1,
`criu/sockets.c` only queries these for AF_UNIX/AF_NETLINK, not TCP sockets.
Use the newer CRIU for HTTP-app experiments; a successful kernel feature check
alone does not establish application compatibility.

Source: https://github.com/checkpoint-restore/criu/blob/v4.2.1/criu/sockets.c
