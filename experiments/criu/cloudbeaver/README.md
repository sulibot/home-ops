# CloudBeaver CRIU compatibility pilot

This is an isolated, disposable **experiment**, not a production hibernator. It
uses CloudBeaver 26.1.1's pinned image and a pinned CRIU 4.2.1 binary. A small
supervisor runs the original Java server as UID 8978 on its original port 8978,
fronts it on port 8080, and offers management/health on port 8082. The first
real HTTP request after checkpoint restores the same process before proxying.
The two-cycle native Talos test passed with image digest
`sha256:3859b5bd3cbce2f12c84eaf5bbb1ab20e876609f26d2c829c62cd1d7cdf00998`;
see [RESULTS.md](RESULTS.md) for measurements and limits.

The Pod manifest uses only disk-backed `emptyDir` workspace and checkpoint
storage. It has no live PVC, database credentials, Service, Ingress, or service
account token, and is fixed to `solwk03`. The powerful capability set (including
`SYS_RESOURCE` for cross-UID resource-limit access) and unconfined seccomp are
**not** suitable for broad production rollout. Snapshot
bytes may contain application memory and must be protected like secrets.
CRIU's `--file-locks` is required by CloudBeaver's JVM/H2 workspace locks; the
pilot assumes this lone process is the only lock user. That assumption must be
verified separately for any real workspace or shared filesystem.

Build locally (linux/amd64) from this directory, push to the internal registry,
pin the resulting immutable digest in `pod.yaml`, and have the owner review the
exact manifest before any cluster apply. The manifest currently pins the tested
image. For example:

```sh
docker build --platform linux/amd64 -t zot.sulibot.com/experiments/criu-cloudbeaver:pilot1 .
```

After the owner deploys the disposable Pod, run:

```sh
python3 test_cycle.py --kubeconfig /Users/sulibot/code/home-ops/talos/clusters/cluster-101/kubeconfig
```

The test port-forwards only to this Pod, checks a real CloudBeaver `GET /`,
manual checkpoint, an HTTP-triggered restore, automatic idle checkpoint, and a
second HTTP-triggered restore. It checks original PID and a random identity
held only in the Java process environment, plus at least
64 MiB reduction in both cgroup anonymous and total memory. The supervisor's
`/status` does not wake the application; the original `/status` app endpoint
is used internally to gate checkpointing.

The pinned base image and CRIU artifact fix those inputs. Ubuntu `apt` packages
are not snapshot-pinned, so a future rebuild may not reproduce the same image;
deploy the verified image by digest after a successful build and test.

Limits: this proxy deliberately does not support WebSocket upgrades, streaming,
or chunked uploads. It is unsuitable for real database sessions or concurrent
production traffic. A dump or restore failure is an experiment failure, not
authorization to add `--tcp-established`, broaden privileges, or modify a live
deployment. Checkpoint data in `emptyDir` vanishes with the Pod; the scheduler
memory request is not reduced merely because the process is asleep.
