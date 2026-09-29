# Zeropod synthetic TCP canary

These manifests are an isolated, manual test for one Zeropod
checkpoint/restore cycle on `solwk03`. They use the previously pushed synthetic
image by digest. The target container directly runs `workload.py`, with no
supervisor and no added Linux capabilities. Its process allocates and touches
128 MiB, keeps a random identity only in memory, and reports that identity,
its PID, and a counter at `/state` on TCP port 8081.

The original image's script listens only on `127.0.0.1`, which cannot be reached
from another Pod. The ConfigMap mounted over that script here listens on `::`
with dual-stack enabled. This is essential for the cluster's IPv6-first Pod
addresses. The code otherwise retains the original memory allocation, identity,
counter, and file activity. The client is a separate default-runtime Pod pinned
to `solwk01`, so its request traverses the Cilium network path to the target
Pod IP. No port-forward or localhost shortcut is involved.

## One-cycle test

Prerequisites: the `zeropod` RuntimeClass, the `solwk03` CRI handler, and the
Zeropod manager DaemonSet must be healthy. Confirm that the target node's
handler is active before creating the target Pod. The test creates only a new
namespace, two Pods, and two ConfigMaps.

From the repository root:

```sh
kubectl kustomize experiments/criu/zeropod
kubectl apply -k experiments/criu/zeropod
kubectl -n zeropod-experiment wait --for=condition=Ready pod/zeropod-memory-canary --timeout=120s
kubectl -n zeropod-experiment wait --for=condition=Ready pod/zeropod-tcp-client --timeout=120s
kubectl -n zeropod-experiment get pods -o wide
```

The target should be on `solwk03`, and the client should be on `solwk01`. Get
the target Pod IP and run exactly one baseline request, a 45-second idle
interval, and one wake request:

```sh
POD_IP=$(kubectl -n zeropod-experiment get pod zeropod-memory-canary -o jsonpath='{.status.podIP}')
kubectl -n zeropod-experiment exec zeropod-tcp-client -- \
  python3 /opt/criu-demo/test_cycle.py --host "$POD_IP" --idle-seconds 45
```

The client prints the first state immediately and announces its idle period.
The target has `zeropod.ctrox.dev/scaledown-duration: 15s`, leaving about 30
seconds for checkpoint completion before the wake request. While it sleeps,
check manager and CRI logs for a completed checkpoint, and compare target
container memory before and during idle (for example with `kubectl top pod
--containers -n zeropod-experiment`). A PASS requires the second request to
return over TCP and preserve the memory-only identity and PID. The PID alone
is weak evidence because a fresh process can also become PID 1; the random
identity is the decisive continuity check. A request made before checkpoint
completion does not prove restore, so confirm the checkpoint log or memory
drop before accepting PASS. A matching identity while the process remains
awake is a false positive. In the first live attempts, CRIU's tmpfs dump failed
because GNU tar could not execute its compressor on Talos. Zeropod fell back
to a cold container restart; the memory-only identity changed, so these
attempts **failed** the continuity check. Bundling `gzip` alone did not fix
it: GNU tar 1.34 invokes `/bin/sh` for compression, but Talos has no shell.
After installing a corrected bootstrap image, recreate the target Pod so it
starts a new shim process with checkpointing enabled, and require a completed
checkpoint before judging the next wake request. Record wake latency and test
a second cycle only after the first succeeds.

If the target fails or the request times out, inspect the manager Pod logs and
Talos CRI logs on `solwk03` before deleting the test. To clean up after
capturing results:

```sh
kubectl delete -k experiments/criu/zeropod
```

No Deployment or liveness probe is used in this first canary. `restartPolicy:
Never` ensures an application crash is visible rather than silently restarted.
The `/state/counter` file is deliberately incidental; the identity is never
written there. This test does not validate application-specific sockets,
database connections, persistent volumes, KEDA behavior, or lifecycle after
a node reboot.
