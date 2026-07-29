#!/usr/bin/env bash
# Use the OpenBao Transit recipient through the scoped sops AppRole. Plain
# `sops` continues to use the retained age recipient for offline recovery.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/openbao-approle-exec.sh" sops sops "$@"
