# Zeropod on this Talos cluster

Investigation: 2026-09-28. This is a deployment assessment, not an installed runtime.

Zeropod is the closest existing project to the desired workflow: checkpoint an
idle container to disk, release its application memory, and restore on incoming
TCP traffic. v0.13.0 supports HTTP/TCP probe detection and optional in-place
resource-request adjustment. Exec/gRPC probes can wake sleeping applications.

Do **not** apply the upstream production installer directly to this cluster.
The v0.13.0 installer assumes systemd, `/etc/containerd/config.toml`,
`/run/containerd/containerd.sock`, writable `/etc/criu`, and `SystemdCgroup=true`.
Talos uses a different service manager and CRI configuration/layout. Upstream's
Talos compatibility issue remains open and recommends a system extension.

A repeatable integration would need:

1. A pinned Talos-compatible system extension containing the shim, CRIU and its
   runtime dependencies; account for the shim's configuration and binary paths.
2. An opt-in runtime handler in the generated Talos machine configuration via
   `CRICustomizationConfig`, preserving Talos' existing default runtime and
   cgroup configuration. Wire its extension through Terragrunt's schematic
   source, not just generated `talenv.yaml` or an imperative node edit.
3. A Talos-specific Zeropod manager deployment and RuntimeClass, initially
   selecting one worker and disposable workloads only. Validate eBPF/Cilium
   compatibility, probes, restore failure recovery and actual memory accounting.
4. App-by-app tests for sockets, external databases, PVC state, background jobs,
   and idle detection. Avoid letting KEDA delete a Pod that holds a local
   checkpoint; choose one lifecycle controller for each enrolled app.

This does not require enabling containerd's experimental CRI image restore.
Do not enable that option as a shortcut: the patched containerd release disables
it by default because it cannot enforce the destination security context.

The adjacent same-Pod experiment tests the Talos kernel/CRIU mechanism without
changing a worker's runtime configuration. It is **not** equivalent to a
production Zeropod installation or a generic application wrapper.

Sources inspected:

- https://github.com/laravel/zeropod/issues/173
- https://github.com/ctrox/zeropod/blob/v0.13.0/docs/getting_started.md
- https://github.com/ctrox/zeropod/blob/v0.13.0/docs/configuration/README.md
- https://github.com/ctrox/zeropod/blob/v0.13.0/cmd/installer/main.go
- https://github.com/containerd/containerd/security/advisories/GHSA-p7v4-vr35-mj6f
