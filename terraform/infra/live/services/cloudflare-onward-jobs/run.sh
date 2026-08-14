#!/usr/bin/env bash
set -euo pipefail

unit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$unit_dir"

if ! command -v op >/dev/null 2>&1; then
  echo "1Password CLI (op) is required." >&2
  exit 1
fi

if ! command -v terragrunt >/dev/null 2>&1; then
  echo "terragrunt is required." >&2
  exit 1
fi

exec op run --env-file="$unit_dir/.env.op" -- terragrunt "$@"
