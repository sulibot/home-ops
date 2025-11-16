#!/usr/bin/env bash
set -euo pipefail

input="${1:-}"

if [[ -z "${input}" ]]; then
  echo ""
  exit 0
fi

# Strip leading "cluster-" if provided.
arg="${input#cluster-}"

# If a directory with this name exists, use it directly.
if [[ -d "terraform/infra/live/cluster-${arg}" ]]; then
  echo "${arg}"
  exit 0
fi

# If the argument is numeric, try to resolve it to a cluster name by reading cluster_id.
if [[ "${arg}" =~ ^[0-9]+$ ]]; then
  for dir in terraform/infra/live/cluster-*; do
    [[ -d "${dir}" && -f "${dir}/cluster.hcl" ]] || continue
    if rg --fixed-strings --quiet "cluster_id     = ${arg}" "${dir}/cluster.hcl"; then
      basename "${dir}" | sed 's/^cluster-//'
      exit 0
    fi
  done
fi

# Fall back to the provided value (without prefix).
echo "${arg}"
