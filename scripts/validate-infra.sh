#!/usr/bin/env bash
# Offline validation of the infrastructure parameter layers. Run locally or
# in CI; fails fast on the mistakes the layout can't prevent by itself:
#   1. site.yaml edited without regenerating site.json / INVENTORY.md
#   2. a cluster.hcl missing required contract fields
#   3. terragrunt HCL that no longer parses
#   4. nix hosts that no longer evaluate
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

FAILURES=0
fail() { echo "✗ $1" >&2; FAILURES=$((FAILURES + 1)); }
ok() { echo "✓ $1"; }

# ── 1. Generated site facts are in sync ─────────────────────────────────────
./scripts/sync-site-facts.sh >/dev/null
if git diff --quiet -- site.json nix/site.json INVENTORY.md; then
  ok "site.json / nix/site.json / INVENTORY.md in sync with site.yaml"
else
  fail "site.yaml changed without regenerating derived files (run scripts/sync-site-facts.sh and commit)"
  git --no-pager diff --stat -- site.json nix/site.json INVENTORY.md
fi

# ── 2. Cluster contract fields ───────────────────────────────────────────────
CONTRACT_KEYS=(enabled cluster_name cluster_id tenant_id bootstrap_node_ipv4 kubernetes_api_host talos_apply_mode)
for cluster_hcl in terraform/infra/live/clusters/cluster-*/cluster.hcl; do
  missing=()
  for key in "${CONTRACT_KEYS[@]}"; do
    grep -qE "^\s+${key}\s*=" "$cluster_hcl" || missing+=("$key")
  done
  if [ ${#missing[@]} -eq 0 ]; then
    ok "contract complete: ${cluster_hcl}"
  else
    fail "${cluster_hcl} missing contract keys: ${missing[*]}"
  fi
done

# ── 3. Terragrunt HCL syntax (offline and secret-free) ──────────────────────
# Feed each file to the formatter parser via stdin so validation does not
# evaluate live backends, dependency outputs, encrypted locals, or host files.
while IFS= read -r hcl_file; do
  if terragrunt hcl fmt --stdin < "$hcl_file" >/dev/null 2>&1; then
    ok "terragrunt HCL: ${hcl_file#terraform/infra/}"
  else
    fail "terragrunt HCL: ${hcl_file#terraform/infra/}"
  fi
done < <(find terraform/infra -name '*.hcl' -not -name '.terraform.lock.hcl' \
  -not -path '*/.terragrunt-cache/*' | sort)

# ── 4. Nix hosts evaluate ────────────────────────────────────────────────────
if command -v nix >/dev/null 2>&1; then
  for host in $(cd nix && nix eval --json .#nixosConfigurations --apply builtins.attrNames 2>/dev/null | jq -r '.[]'); do
    if (cd nix && nix eval ".#nixosConfigurations.${host}.config.system.build.toplevel.drvPath" >/dev/null 2>&1); then
      ok "nix eval: ${host}"
    else
      fail "nix eval: ${host}"
    fi
  done
else
  echo "~ nix not installed; skipping flake eval"
fi

echo
if [ "$FAILURES" -gt 0 ]; then
  echo "FAILED: ${FAILURES} problem(s)" >&2
  exit 1
fi
echo "All infra validation checks passed."
