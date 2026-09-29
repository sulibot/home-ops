# Zeropod v0.13.0 bootstrap for Talos v1.14.1 (amd64)

This is a pilot payload for a Talos worker. It avoids the
upstream Zeropod installer, which writes `/etc/containerd` and uses systemd.
The image copies binaries and their runtime libraries into the worker's
writable `/var/lib/zeropod` directory. Talos's `CRICustomizationConfig` then
adds an opt-in `zeropod` handler; the existing `runc` handler stays default.

## Build and use

```sh
docker buildx build --platform linux/amd64 --load -t zeropod-talos-bootstrap:v0.13.0-poc talos/extensions/zeropod
```

For subsequent builds, push the image to the cluster registry and replace the
bootstrap image in [`daemonset.yaml`](./daemonset.yaml) with its digest. The
current pilot manifest is pinned to the tested image digest and to
`solwk03` and uses a `hostPath` mount of `/var/lib/zeropod` at `/host` for the
bootstrap init. That init needs no privileged security context, host root,
containerd socket, systemd socket, or `/etc/criu` mount. The manager mounts
the same directory at both `/opt/zeropod` (for `shim.json` updates) and
`/var/lib/zeropod` (for checkpoint data). The upstream BPF preparation and
manager host mounts remain in the DaemonSet. Its upstream manager image is
pinned by digest.

The Kustomize manifests include the upstream v0.13.0 Migration CRD (vendored),
minimal pilot RBAC, an opt-in RuntimeClass pinned to `solwk03`, and a
cert-manager self-signed Ed25519 CA. The upstream manager always starts its
TLS node server and requires that CA key. The Secret is mounted with
`tls.crt`/`tls.key` remapped to its expected `ca.crt`/`ca.key`. Cert-manager
must be healthy and `ca-cert` must exist before the DaemonSet can start.
Pilot RBAC permits only reads of Pods, Nodes, and Migrations. Migration and
capacity eviction are deliberately unavailable with these permissions.

The `solwk03` pilot already has the TOML from
[`cri-customization.yaml`](./cri-customization.yaml) applied to its Talos
machine configuration as a named `CRICustomizationConfig`. It mirrors the
worker's observed `runc` `base_runtime_spec` and `ShimCgroup`, and forwards
the exact pod annotation set from Zeropod v0.13.0. Select the runtime only for
pilot Pods through the `RuntimeClass` (`handler: zeropod`). The DaemonSet and
RuntimeClass both target `solwk03`. Never change the CRI default runtime to
Zeropod.

The bootstrap image copies the upstream static shim and `zeropod-netinfo`
from the pinned v0.13.0 installer image. A tiny static launcher prepends
`/var/lib/zeropod/bin` to `PATH` (for `criu`, GNU `tar`, GNU `gzip`, and
`zeropod-netinfo`)
and sets `CRIU_CONFIG_FILE` to the upstream installer defaults. It execs the
original shim without changing its arguments. CRIU 4.2.1 is from the pinned
upstream CRIU image; its glibc loader and shared libraries are bundled under
`/var/lib/zeropod/lib`, and its ELF interpreter and RPATH are rewritten to
those absolute paths. The Docker build verifies the resulting binaries in an
Alpine (musl) image. GNU tar 1.34 normally runs `/bin/sh -c gzip` when
creating compressed archives, and Talos has no `/bin/sh`; merely bundling
`gzip` did not fix the first live checkpoint failures. This build patches the
tar compression path to execute the bundled `gzip` directly. The current
source uses Debian Bookworm's `1.34+dfsg-1.2+deb12u1` source package, with
all three source files SHA256-pinned. Debian's patches fix CVE-2023-39804
(PAX extended-header/xattr crash) and CVE-2022-48303 (base-256 decoder
boundary read), which the vanilla tar 1.34 bundle lacked. The Dockerfile's
build test
performs compressed create/extract inside a chroot **without** `/bin/sh`, in
addition to the bundled-binary smoke checks. Other tar compression programs
retain upstream behavior and are not supported on shell-less Talos. The
repository-local `.gitignore` makes this source patch trackable despite the
repository-wide `*.patch` ignore rule. Bootstrap installs each binary and
library through a temporary file in the same host directory followed by
atomic rename, so a restart does not overwrite a running executable in place.
It preserves an existing `shim.json` and CRIU configuration so manager updates
survive a DaemonSet restart.

## Required pilot checks

The image build tests process startup, not CRIU access to Talos namespaces or
actual checkpoint and restore. Before enrolling an app, confirm on the target
worker that the generated CRI configuration includes only the new handler,
the default `runc` handler is unchanged, the manager becomes Ready, and a
disposable Pod with `runtimeClassName: zeropod` starts. Then exercise idle
checkpoint, actual RSS reduction, TCP wake and response, repeated restore,
probe behavior, and Pod deletion/recreation. Verify that a failure never leaves
a request hanging or a Pod reported Ready with no serving process. Check
checkpoint disk growth in `/var/lib/zeropod` and node reboot behavior before
using stateful workloads. Keep KEDA scale-to-zero disabled for a Zeropod Pod;
KEDA deleting it removes the local checkpoint.

This image is amd64-only and pinned to the upstream image digests in the
Dockerfile. The corrected bundle and opt-in CRI handler are installed only on
`solwk03`. The synthetic canary completed two real checkpoint/restore cycles
with its memory-only identity preserved; its first two attempts, before the
tar patch, failed. This is a one-node experimental validation, not app rollout
approval. The **currently deployed** digest still contains the vanilla tar
1.34 build: the Debian-patched source change has been validated through patch
application, but its final image build and live retest are pending. Do not
describe the installed canary as carrying the Debian security fixes. Debian
still lists several open tar issues; CRIU's fixed commands neither use
`--one-top-level` nor incremental archives, and restore reads its own locally
generated checkpoint rather than an externally supplied archive. This narrows,
but does not eliminate, exposure to malformed-archive issues. Probe behavior,
workload compatibility, node reboot, and long-running checkpoint disk usage
remain unverified. The Flux Kustomization remains suspended, and no existing
app should be migrated until the maintained-source image is built, tested,
and these remaining pilot checks are complete.

Upstream references: [Zeropod v0.13.0 installer](https://github.com/ctrox/zeropod/blob/v0.13.0/cmd/installer/main.go),
[Zeropod v0.13.0 configuration](https://github.com/ctrox/zeropod/blob/v0.13.0/api/shim/v1/config.go),
[Talos 1.14 CRI customization](https://github.com/siderolabs/talos/releases/tag/v1.14.0),
[Talos extension paths](https://github.com/siderolabs/extensions/blob/main/README.md),
[CRIU config environment variable](https://criu.org/Configuration_files).

Security sources: [Debian Bookworm tar source](https://packages.debian.org/bookworm/source/tar),
[Debian security tracker](https://security-tracker.debian.org/tracker/source-package/tar).
