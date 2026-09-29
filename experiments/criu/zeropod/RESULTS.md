# Native Zeropod/Talos canary — 2026-09-28 PDT

After recording these results, the disposable `zeropod-experiment` namespace
and its checkpoints were removed. The one-node runtime manager/handler remain;
no production application has been enrolled.

Passed on `solwk03`: Talos 1.14.1, Kubernetes 1.37.0, containerd 2.3.5,
Zeropod 0.13.0, bundled CRIU 4.2.1. Bootstrap image:
`zot.sulibot.com/infra/zeropod-talos@sha256:428af80e10a358ed9237f5964a0d236a005d21d08f62ff06722bb9c183fb7b48`.

The workload used `runtimeClassName: zeropod` with no added capabilities or
privileged workload container. An independent client on `solwk01` reached its
IPv6 Pod IP over Cilium, without port-forwarding. No real app, PVC, credential,
or KEDA scaler was modified by this test.

| Measurement | Observation |
| --- | --- |
| First checkpoint | 199.76 ms |
| First network wake / HTTP response | 111.31 ms (runtime restore 106.48 ms) |
| Second checkpoint | 187.76 ms |
| Second network wake / HTTP response | 116.85 ms (runtime restore 112.39 ms) |
| Third automatic checkpoint | 173.12 ms |
| Awake workload RSS | 144,031,744 B (137.36 MiB) |
| Sleeping workload RSS | 0 B |
| Sleeping whole-Pod RSS / working set | 40,960 B / 536,576 B |
| Latest checkpoint logical disk size | 144,069,274 B (137.40 MiB) |

Both HTTP observations followed actual successful checkpoints/restores in the
Talos CRI log. The random memory-only identity was unchanged; the process kept
PID 1 inside its namespace, and the counter advanced from 15 to 56. The TCP
test exited 0. After the next idle period, read-only kubelet statistics and
checkpoint-directory inspection confirmed another successful sleep.

These figures exclude node-manager/shim overhead and host filesystem page cache.
The manager was about 18 MiB before the test. The Pod's 192 MiB memory request
does not shrink: in-place resource scaling is **not enabled** in this canary.
Do not equate sleeping workload RSS with the entire runtime's memory cost or
additional scheduler capacity. No application latency SLO follows from two
synthetic samples.

The timer was configured for 15 seconds. Network activity observed after a
proxied request delayed the next checkpoint to roughly 41 seconds after that
response; the test used a 45-second idle interval. Idle duration is counted
from runtime-observed network activity, not browser closure alone.

## Talos packaging fixes and remaining gates

The first bundle failed when CRIU's tmpfs archive needed gzip. Adding gzip alone
was insufficient: GNU tar 1.34 invokes `/bin/sh` for compression, and Talos has
no shell. The bundle now includes gzip and a narrowly patched, checksum-pinned
GNU tar that directly executes the packaged gzip for this operation. A shell-less
chroot compression/extraction smoke test and a native manager-container test
passed before the successful CRIU run.

On failed checkpoint attempts, Zeropod disabled checkpointing and subsequently
cold-restarted the process; the memory-identity test correctly failed. This is
an upstream fallback behavior, not durable preservation of arbitrary RAM state.

The tar build's security-patch parity with maintained distro releases still
needs review. Flux reconciliation remains suspended and existing KEDA apps
remain unchanged. Before app enrollment, validate image-specific process trees,
authentication/sessions, external sockets, storage/locks, probes, background
work, scheduler-request resizing, and restart/reboot behavior.
