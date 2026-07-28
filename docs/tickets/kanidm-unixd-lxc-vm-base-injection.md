# Ticket: Kanidm Unix auth (SSH/PAM/NSS) injected into LXC/VM/NixOS base provisioning

- Status: Done
- Priority: Low
- Area: Terraform (terragrunt), Nix
- Created: 2026-07-28

## Summary

Kanidm's own nodes get `kanidm-unixd` for host login. Initial investigation
assumed this was hand-copied per-stack with no shared source — **wrong**.
The actual `main.tf` under `terraform/infra/live/services/kanidm/` is
Terragrunt-generated and gitignored; the real, tracked source is
`terragrunt.hcl`, which already reads a shared
`terraform/infra/live/common/lxc-kanidm-auth.hcl` for
`kanidm_unix_auth_commands` via `read_terragrunt_config`. That shared file
is **already consumed by three stacks** (`kanidm`, `zot-lxc`,
`smallstep-lxc`) — the Terraform-side reusable-module problem this ticket
set out to solve didn't exist; it was solved before this ticket was filed.

(An initial pass built a redundant `terraform/infra/modules/kanidm_unixd_client`
module and edited the generated `main.tf` directly — neither took effect,
since the generated file is regenerated from `terragrunt.hcl` on every
`terragrunt` run and isn't tracked. Removed once the real mechanism was
found; see `git log` on this file if that detour is ever relevant again.)

What was actually missing: a **Nix**-side equivalent for NixOS LXC/VM
guests. That's real, new work.

## Design

**Terraform (Debian LXC/VM):** nothing to build — already solved via
`terraform/infra/live/common/lxc-kanidm-auth.hcl`. Any future
`live/services/*` stack opts in the same way `zot-lxc`/`smallstep-lxc` do:
```hcl
kanidm_auth = read_terragrunt_config(find_in_parent_folders("common/lxc-kanidm-auth.hcl")).locals
# ...
kanidm_unix_auth_commands = ${jsonencode(local.kanidm_auth.kanidm_unix_auth_commands)}
```

**Nix (NixOS LXC/VM guests):**
- New `nix/modules/profiles/kanidm-client.nix`, opt-in (not imported by
  `base.nix`, so it doesn't change every guest by default):
  ```nix
  services.kanidm = {
    package = pkgs.kanidm_1_10;  # unversioned pkgs.kanidm/kanidm_1_4/1_7 are EOL/removed on this pin
    enableClient = true;
    clientSettings.uri = "https://idm.sulibot.com";
    enablePam = true;
    unixSettings.pam_allowed_login_groups = [ "posix_group" ];
  };
  ```
  Note: current upstream nixpkgs (`master`) renamed this API to
  `client.enable`/`unix.enable` with a nested `unix.settings.kanidm.*`, but
  **this repo's flake pins an older nixpkgs revision** (`b6018f8`) that
  still uses the flat `enableClient`/`enablePam`/`clientSettings`/
  `unixSettings` names — confirmed by evaluating
  `nixosConfigurations.nixtest01.options.services.kanidm` directly rather
  than trusting upstream docs. Also had to pin `package` explicitly:
  the module's default (`kanidm_1_4`) has been removed from nixpkgs, and
  the unversioned `pkgs.kanidm` alias resolves to 1.7.4 which is marked
  insecure/EOL. Verified with
  `nix eval .#nixosConfigurations.nixtest01.config.system.build.toplevel.drvPath`
  (full config evaluation succeeds against the pilot `nixtest01` host with
  the module temporarily wired in, then reverted — actual `nix build`
  needs an `x86_64-linux` builder since these hosts aren't the same arch
  as a macOS dev machine, pre-existing and unrelated to this module). It
  wires the daemons and NSS module (`system.nssModules`/`nssDatabases`)
  automatically.
- **PAM stack wiring deliberately deferred.** The NixOS kanidm module only
  registers the systemd daemons and NSS databases — it does **not** touch
  `/etc/pam.d` for you, and upstream doesn't publish a canonical
  `security.pam.services.*.text` snippet the way the Debian package's
  postinst does. Getting PAM ordering wrong risks SSH lockout across every
  Nix guest that imports the profile. Since these guests already use
  key-based SSH (`base.nix` sets `PermitRootLogin = "prohibit-password"`),
  password-login-via-Kanidm isn't blocking anything — NSS-only (Kanidm
  users/groups resolvable, e.g. for file ownership or `id` lookups) ships
  now; interactive PAM password login is a follow-up once the exact
  `pam.d` stack is validated on a throwaway host.

## Acceptance criteria

- [x] Confirmed the Terraform-side reusable mechanism already exists
      (`common/lxc-kanidm-auth.hcl`); no redundant module added.
- [x] `nix/modules/profiles/kanidm-client.nix` exists, is importable, and
      full config evaluation succeeds for a host that imports it
      (`nixosConfigurations.nixtest01`, temporarily, then reverted).
- [x] Documented (in this file) how a future LXC/VM/Nix host opts in.

## Follow-ups (not this ticket)

- Roll Kanidm Unix auth out to specific existing NixOS hosts (`nixtest01`,
  `nixbuild01`), one at a time — this ticket only builds and validates the
  opt-in module, it doesn't enable it anywhere.
- Validate and add the NixOS PAM stack lines for interactive Kanidm login.
