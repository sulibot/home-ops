# Same-Pod CRIU experiment

This is a disposable probe, not a generic app proxy. A small HTTP supervisor
stays alive while CRIU dumps and terminates its 128 MiB child process. After
30 seconds without a `/request` (configurable with `IDLE_SECONDS`), it sleeps
automatically; the next `/request` restores the child and forwards to its own
localhost HTTP listener. `/status` never wakes it. The child holds a random
identity only in memory, so the test can distinguish restore from cold restart.
It does not use containerd CRI restore, change node config, or preserve state
beyond the Pod lifetime. Checkpoints are on disk-backed `emptyDir`; they can
contain all process memory, so use only synthetic data.

The default Pod uses `privileged: false` with CHECKPOINT_RESTORE, SYS_PTRACE,
SYS_ADMIN, NET_ADMIN, and SYS_TIME capabilities plus unconfined seccomp. This
profile passed both HTTP sleep/wake cycles on Talos; it is still powerful, and
the smallest capability set has not been established. The Pod has no host
mounts, host namespaces, Service, or service account token. It is pinned to
`solwk03`, an active worker. Review the manifest and image before use.

Build for the cluster architecture:

```sh
docker buildx build --platform linux/amd64 -t zot.sulibot.com/experiments/criu:20260928-poc4 .
```

After the image is in the internal registry and `pod.yaml` points to its
immutable digest, apply it and wait for the Pod to be Ready:

```sh
kubectl --kubeconfig /absolute/path/to/cluster-101/kubeconfig apply -f pod.yaml
kubectl --kubeconfig /absolute/path/to/cluster-101/kubeconfig -n criu-experiment wait pod/process-checkpoint --for=condition=Ready --timeout=90s
python3 test_cycle.py --kubeconfig /absolute/path/to/cluster-101/kubeconfig
```

For a repeat run, first delete this exact Pod and wait for deletion to finish
before applying `pod.yaml` again:

```sh
kubectl --kubeconfig /absolute/path/to/cluster-101/kubeconfig -n criu-experiment delete pod/process-checkpoint --wait=true --timeout=60s
```

The script port-forwards only to localhost, checks one manual and one automatic
sleep/wake cycle, verifies the memory-only identity and counter, and requires at
least 64 MiB of anonymous and total cgroup memory to be freed. The supervisor
fsyncs and evicts checkpoint archive file cache for accurate accounting. On
failure, inspect `dump.log` or `restore.log` in `/state/checkpoints/cycle-N`.
The Pod still reserves 256 MiB in Kubernetes while asleep; this experiment
measures actual use, not scheduler capacity recovery. It does not test any real
app, established client connections, cross-Pod restore, checkpoint durability
after Pod deletion, or integration with KEDA. See [RESULTS.md](RESULTS.md) for
the native Talos measurements and failure history.

Both the initial privileged profile and the default capability profile passed
two same-Pod HTTP cycles on Talos 1.14.1. With the default profile, total
cgroup memory fell from 157,470,720 bytes to 13,107,200 bytes while asleep,
then to 12,886,016 bytes on the automatic cycle. Wake requests took 584 ms and
726 ms end to end. The child's memory-only identity remained the same and its
counter advanced after both restores.

The image uses the official Debian forky amd64 digest
`sha256:61c8340200f7d4e440dd0c52ac81628060da77410108afaebb23d38e43f39fa1`
and Debian's `criu=4.2.1-1`. Deploying the built image by its registry digest
repeats the exact bytes; rebuilding from apt later depends on those pinned
package versions still being available in the rolling forky repository.
CRIU 4.1.1 could checkpoint the initial socket-free process, but failed on the HTTP listener's socket options on the
Talos kernel; upstream CRIU 4.2.1 handles this case.
