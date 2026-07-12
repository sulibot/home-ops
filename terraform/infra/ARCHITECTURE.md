# Infrastructure parameter architecture

How parameters are organized, where to change what, and the conventions that
keep this understandable. If you're about to edit infra and aren't sure where
a value lives, start here.

## The layers

Data flows down; behavior lives at the bottom. **A fact lives in exactly one
place, and you change it at the highest layer that owns it.**

| # | Layer | Where | Owns |
|---|-------|-------|------|
| 0 | Site facts | `site.yaml` (repo root) | Cross-toolchain truths: domain, DNS/NTP, tenant registry, Proxmox nodes, LXC/VM guest inventory. Consumed by Terragrunt, Nix, and (eventually) Flux via the generated `site.json`. |
| 1 | Terraform-facing facts | `live/common/*.hcl` | Versions, BGP/SDN/addressing math, install schematic, credentials, secrets. Some re-export site facts as HCL locals (adapters). |
| 2 | Aggregation | `live/clusters/_shared/context.hcl` | Re-exports common + cluster-wide defaults (VM sizing, Talos defaults, artifact-catalog handoffs). |
| 3 | Cluster contract | `live/clusters/<id>/cluster.hcl` | Identity + per-cluster choices + node inventory. The only file a cluster owns. |
| 4 | Behavior templates | `live/clusters/_shared/units/*.hcl` | *How* a unit works: hooks, dependencies, input wiring. Cluster-agnostic; reads layers 0-3. |
| 5 | Stubs | `live/clusters/<id>/<unit>/terragrunt.hcl` | ~18-line include pointers + rare per-cluster input overrides. |
| 6 | Mechanism | `modules/*/` | Pure Terraform. Everything via variables. Zero policy, zero defaults that encode site decisions. |

Parallel trees at the same layer as 0/3: `nix/` (NixOS guest config),
`kubernetes/` (Flux/GitOps), `talos/` (generated cluster artifacts).

## Where do I change X?

| Change | File |
|---|---|
| Bump Talos / Kubernetes / provider version | `live/common/versions.hcl` |
| Re-IP or add a Proxmox node; move the API endpoint | `site.yaml` → regenerate `site.json` |
| Change DNS/NTP servers or the base domain | `site.yaml` |
| Add / resize / move an LXC or VM service guest | `site.yaml` (`services:`), then `terragrunt apply` in its unit |
| Add a node to a cluster; change apply mode; enable/disable a cluster | `live/clusters/<id>/cluster.hcl` |
| Change how bootstrap / config / flux behaves (all clusters) | `live/clusters/_shared/units/<unit>.hcl` |
| Kernel args / Talos extensions | `live/common/install-schematic.hcl` |
| BGP ASNs, addressing patterns, SDN | `live/common/network-infrastructure.hcl` |
| What's on a NixOS guest | `nix/hosts/<hostname>/` |
| Cloudflare Access / WARP tiers | `live/services/cloudflare-access/` |
| Secrets | `live/common/secrets.sops.yaml` (SOPS) |

## Naming grammar

The suffix tells you the shape. Never guess:

| Suffix | Shape | Example |
|---|---|---|
| `_ipv4`, `_ipv6`, `_ip` | bare address | `bootstrap_node_ipv4 = "10.101.0.11"` |
| `_cidr` (or `_ipv4_cidr`) | address with prefix | `ipv4_cidr = "10.200.0.52/24"` |
| `_host` | hostname or bare IP, no scheme | `kubernetes_api_host = "fd00:101::10"` |
| `_url` / `_endpoint` | full URL with scheme | `api_endpoint = "https://10.10.0.2:8006/api2/json"` |
| `_id` | numeric identity | `vm_id`, `tenant_id`, `cluster_id` |
| `_pattern` | format string, `%d` = tenant/cluster id | `pods_ipv4_pattern` |

Role enum: `machine_type = "controlplane" | "worker"` everywhere. (The
`control_plane` bool in the compute layer is legacy; unify when next touching
`cluster_core` — see Deferred.)

## Derivation and overrides

The addressing scheme is systematic; source files store **only the deciding
numbers** and everything else is computed:

| Derived value | Formula |
|---|---|
| IPv4 | `10.<tenant>.0.<suffix>` |
| IPv6 | `fd00:<tenant>::<suffix>` |
| vm_id | `<tenant> * 1000 + <suffix>` |
| Gateways | `10.<tenant>.0.254` / `fd00:<tenant>::fffe` |
| Bridge | tenant `mode: sdn` → `vnet<tenant>`; `mode: vlan` → `vmbr0` + VLAN `<tenant>` |
| Node loopbacks | `10.<tenant>.254.<suffix>` / `fd00:<tenant>:fe::<suffix>` |
| Per-node BGP ASN | `4210000000 + tenant*1000 + suffix` |

Rules:
- Every derived value has an escape hatch: an `override:` map on the entry.
  Overrides are exceptional and self-announcing in review — if you're writing
  one, say why in a comment.
- Derivation kills grep-ability, so `INVENTORY.md` (generated) materializes
  every computed value in a human-readable, greppable table. Edit sources,
  read the inventory. CI fails if it's stale.

## The null/try rule (hard-won)

Terraform fills absent `optional()` object fields with **literal `null`**, and
`try()` happily returns that null instead of your fallback. This shipped a
real bug (empty BGP configs cluster-wide).

- **Fallback for a possibly-null value:** `x != null ? x : default` or
  `coalesce(x, default)`.
- **`try()` is only for "this path may not exist / may error"** — never for
  null-coalescing.

## Environment-variable knobs

These are real parameters with real blast radius. All of them:

| Variable | Consumed by | Effect |
|---|---|---|
| `TALOS_BOOTSTRAP_MODE=true` | bootstrap, cilium-bootstrap, flux units | Force bootstrap-time behavior on a healthy cluster |
| `TALOS_APPLY_MODE=<mode>` | apply unit | Override apply mode (`auto`, `staged_if_needing_reboot`, ...) |
| `TALOS_REGENERATE_SECRETS=1` | secrets unit | Allow plan/apply of cluster PKI (otherwise excluded) |
| `TALOS_DESTROY_SECRETS=1` | secrets unit | Allow destroy of cluster PKI |
| `TALOS_INSTALL_WIPE=true` | config units | Set install wipe flag in machine configs |
| `CNPG_RESTORE_MODE=NEW_DB\|RESTORE_REQUIRED` | compute, flux units | Database bootstrap posture |
| `CNPG_NEW_DB=true` | compute, flux units | Shorthand for `CNPG_RESTORE_MODE=NEW_DB` |
| `CNPG_BACKUP_MAX_AGE_HOURS` | compute, flux units | Freshness threshold for restore preflight |
| `CNPG_PREFLIGHT_SKIP=true` | compute unit | Skip the CNPG restore preflight entirely |
| `SOPS_AGE_KEY_FILE` | flux unit, scripts | Age key for SOPS decryption |
| `NIXOS_RELEASE`, `PVE_NODE` | `scripts/fetch-nixos-lxc-template.sh` | Template fetch parameters |

Adding a knob? Add it here in the same commit.

## Terragrunt gotchas encoded in the layout

- `exclude` blocks are **not merged from included files** — stubs declare the
  block, templates expose the condition as `locals.exclude_unit`.
- Generated files (`providers.tf`, `main.tf`, `backend.tf`) are gitignored;
  the `terragrunt.hcl` generate block is the source of truth.
- `mock_outputs` lists only outputs the unit actually consumes.

## Deferred (known, intentional)

- `machine_type` enum vs `control_plane` bool unification (touches
  `cluster_core` module schema).
- Module-internal variable renames to the grammar (`public_ipv4` inside
  `talos_config`'s node-map schema, etc.) — do when next editing those
  modules.
- Flux `postBuild.substituteFrom` consumption of site facts in `kubernetes/`
  (would let manifests reference `${SITE_DOMAIN}` etc.).
- kanidm's per-container definitions stay hand-written in its heredoc
  (identity system; conversion risk outweighs dedup value).
