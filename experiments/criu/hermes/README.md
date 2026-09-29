# Disposable Hermes dashboard Zeropod pilot

This is **not** the real Hermes deployment. It creates one isolated dashboard
Pod on `solwk03` and one small test client on `solwk01`; there is no Service,
Gateway route, production PVC, 1Password item, bot token, model key, host
mount, or service-account token. The Hermes home is a disk-backed `emptyDir`,
so deleting the Pod discards its workspace. Authentication is mandatory:
`bootstrap.py` generates a fresh random password, Hermes scrypt hash, and
signing key on each container start without logging plaintext; the password
file is in a 1 MiB tmpfs and the test reads it into local process memory only.
The pinned image's root bootstrap then drops Hermes to UID 10000. A tiny
memory-only identity server runs in the same container solely to distinguish
CRIU restore from a cold container restart.

The target uses only the opt-in `zeropod` RuntimeClass, with
`dashboard=9119` as the TCP wake port and a 30-second idle timer. The extra
identity listener on 9118 does **not** drive waking. A one-time startup exec
probe checks IPv4 loopback; there are no recurring probes. The test client
uses the target's IPv4 Pod IP because Hermes binds `0.0.0.0` while this
cluster prefers IPv6 Pod addresses. No LLM request or tool execution is made.

Only after the generic Zeropod canary and manager are healthy, a reviewer may
apply this exact disposable package:

```sh
kubectl --kubeconfig talos/clusters/cluster-101/kubeconfig apply -k experiments/criu/hermes
python3 experiments/criu/hermes/test_cycle.py \
  --kubeconfig talos/clusters/cluster-101/kubeconfig
```

The script waits for both Pods, verifies `/api/status` advertises basic auth,
logs in using the throwaway credential and checks `/api/auth/me`, then waits
for at least 64 MiB of actual container memory to disappear (and at most
64 MiB remain) before sending a real cross-node TCP wake request. It requires
the in-memory identity and counter to survive, the original password to
still log in, and repeats the cycle once. It prints latency/memory figures,
never the password, hash, signing key, or session cookie. A valid response
*without* the memory drop is not accepted as a checkpoint result. Inspect the
matching Zeropod/CRI logs for successful CRIU dump and restore before
declaring application compatibility; the script cannot prove that log event
on its own. A dashboard process restart inside a still-running container also
needs to be ruled out from those logs. Confirm no gateway process or bot
long-poll runs inside the dashboard Pod, since the dashboard UI has controls
capable of starting one.

This Pod has not been deployed or tested on native Talos yet. Native success
would still not validate real credentials, persistent CephFS, WebSocket chat,
active sessions, open external connections, node reboot, or safe production
hibernation. Kubernetes continues to reserve its 512 MiB request while it is
checkpointed.

After collecting logs, remove only this disposable namespace:

```sh
kubectl --kubeconfig talos/clusters/cluster-101/kubeconfig delete -k experiments/criu/hermes
```

Sources: [Hermes dashboard auth](https://github.com/NousResearch/hermes-agent/blob/v2026.9.24/website/docs/user-guide/features/web-dashboard.md),
[Hermes image bootstrap](https://github.com/NousResearch/hermes-agent/blob/v2026.9.24/docker/stage2-hook.sh),
[Zeropod v0.13 annotations](https://pkg.go.dev/github.com/ctrox/zeropod@v0.13.0/api/shim/v1).
