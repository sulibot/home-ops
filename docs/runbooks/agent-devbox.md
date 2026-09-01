# Persistent agent devbox

`agent-devbox01` is a low-idle-footprint NixOS LXC for persistent repository
work with Codex CLI and Claude Code. It coordinates deterministic validation;
it is not the database or browser-test worker.

## Resource envelope

| Property | Value |
| --- | --- |
| Proxmox node | `pve02` (i5-14500) |
| VMID | `200210` |
| IPv4 | `10.200.0.210/24` |
| IPv6 | `fd00:200::210/64` |
| CPU ceiling | 4 cores |
| Memory ceiling | 4096 MB |
| Swap allowance | 2048 MB |
| Root disk ceiling | 64 GB on `rbd-vm` |

For an LXC, `memory_mb` is a cgroup ceiling rather than preallocated VM RAM.
Idle pages remain available to the Proxmox host, so VM ballooning is neither
available nor necessary. The 4 GiB ceiling meets Claude Code's documented
minimum; Nix builds are limited to two jobs and two cores to reduce peak
memory pressure. The RBD root disk is thin-provisioned and Nix garbage
collection removes generations older than 14 days.

## Client support boundary

- Codex CLI and Claude Code run directly on the Linux LXC.
- Laptop and phone terminal clients reconnect through SSH and `tmux`.
- ChatGPT/Codex Remote currently connects to a Mac or Windows computer, not a
  Linux LXC. Keep a connected Mac/Windows host for the native ChatGPT Remote
  experience, or use SSH to reach this devbox.
- The repository harness is model-neutral. Both agents invoke the same
  profile and read the same `onward.validation.v1` result.

## Provision and bootstrap

From the home-ops repository:

```bash
cd terraform/infra/live/services/agent-devbox-lxc
terragrunt plan
terragrunt apply
```

The NixOS Proxmox template initially has no managed network or SSH service.
Bootstrap it once from a PVE node:

```bash
pct exec 200210 -- /run/current-system/sw/bin/bash -c '
  ip link set eth0 up
  ip addr add 10.200.0.210/24 dev eth0
  ip route add default via 10.200.0.254
  echo nameserver 10.255.0.53 > /etc/resolv.conf
  export NIX_CONFIG="experimental-features = nix-command flakes"
  export PATH=/run/current-system/sw/bin:$PATH
  nixos-rebuild switch --flake github:sulibot/home-ops?dir=nix#agent-devbox01
'
```

Subsequent deployments are ordinary NixOS rebuilds:

```bash
nixos-rebuild switch --flake ./nix#agent-devbox01 \
  --target-host root@10.200.0.210 \
  --build-host root@10.200.0.210
```

## First user session

The non-root development identity is `agent`:

```bash
ssh -A agent@10.200.0.210
mkdir -p ~/code
cd ~/code
gh auth login
gh repo clone sulibot/onward
tmux new -As onward
```

SSH agent forwarding is sufficient for initial private-repository access.
For unattended fetch/push after the laptop disconnects, authenticate `gh` on
the devbox or provision a narrowly scoped repository credential separately.

Authenticate each agent interactively. Credentials live in the user's home
directory and must never be committed to home-ops or application repositories:

```bash
codex
claude
```

The Nix configuration supplies current Codex and Claude packages from a
separately pinned unstable package set while the operating system remains on
NixOS 25.11. Update and review the flake lock to upgrade those clients.

## Verification flow

Run compact profiles locally on the LXC:

```bash
pnpm verify:affected -- --base origin/main --sha "$(git rev-parse HEAD)"
pnpm verify:security -- --sha "$(git rev-parse HEAD)"
```

Database and database-backed browser profiles remain fail-closed on the LXC.
Selected burst verification runs through an ephemeral GitHub Actions Runner
Controller scale set in Kubernetes. This avoids Docker-in-LXC, privileged LXC
features, and persistent test databases on the coordinator.

The `onward-runner` scale set has zero idle pods and at most three concurrent
runners. Each job receives a 4-core/4-GiB ceiling and an ephemeral 25-GiB RBD
workspace. It is intentionally limited to DB-free fast and security profiles.
Before Flux enables the scale set, confirm that the existing `actions-runner`
GitHub App installation includes the private `sulibot/onward` repository.

## Persistent sessions and durable state

Use one named `tmux` session per repository or task. A disconnected SSH
client does not stop the process:

```bash
tmux new -As onward
tmux list-sessions
tmux attach -t onward
```

Git commits, pushed branches, harness `result.json` files, and CI artifacts
are the durable record. A terminal transcript or agent conversation is not a
substitute for committed state.
