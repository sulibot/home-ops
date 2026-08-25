#!/usr/bin/env bash
# Keep VolSync movers from overlapping and saturating shared Ceph storage.

set -euo pipefail

roots=(
  kubernetes/apps/tier-1-infrastructure
  kubernetes/apps/tier-2-applications
)

errors=0
count=0
seen_slots=""

while IFS= read -r entry; do
  file=${entry%%:*}
  value=${entry#*:}
  value=${value#*:}
  cron=$(printf '%s\n' "$value" | sed -E 's/.*"([^"]+)".*/\1/')
  IFS=' ' read -r minute hours day month weekday extra <<< "$cron"

  if [ -n "${extra:-}" ] || [ "$day" != "*" ] || [ "$month" != "*" ] || [ "$weekday" != "*" ]; then
    echo "[err] ${file}: unsupported VolSync schedule '${cron}'" >&2
    errors=$((errors + 1))
    continue
  fi

  if ! [[ "$minute" =~ ^[0-9]+$ ]] || [ "$minute" -gt 57 ] || [ $((minute % 3)) -ne 0 ]; then
    echo "[err] ${file}: minute must be one of 0,3,...,57; got '${minute}'" >&2
    errors=$((errors + 1))
    continue
  fi

  if ! [[ "$hours" =~ ^([012])-([0-9]+)/3$ ]]; then
    echo "[err] ${file}: hours must be 0-21/3, 1-22/3, or 2-23/3; got '${hours}'" >&2
    errors=$((errors + 1))
    continue
  fi

  phase=${BASH_REMATCH[1]}
  end=${BASH_REMATCH[2]}
  if [ "$end" -ne $((phase + 21)) ]; then
    echo "[err] ${file}: invalid three-hour phase '${hours}'" >&2
    errors=$((errors + 1))
    continue
  fi

  slot=$((phase * 60 + minute))
  if printf '%s\n' "$seen_slots" | cut -d'|' -f1 | grep -Fxq "$slot"; then
    owner=$(printf '%s\n' "$seen_slots" | grep "^${slot}|" | cut -d'|' -f2- | head -1)
    echo "[err] ${file}: schedule '${cron}' collides with ${owner}" >&2
    errors=$((errors + 1))
  else
    seen_slots="${seen_slots}${slot}|${file}"$'\n'
  fi
  count=$((count + 1))
done < <(
  {
    rg --line-number --no-heading '^[[:space:]]+VOLSYNC_SCHEDULE: "[^"]+"' "${roots[@]}"
    while IFS= read -r file; do
      rg --line-number --no-heading '^[[:space:]]+schedule: "[^"]+"' "$file"
    done < <(rg --files "${roots[@]}" | rg '/volsync-replicationsource\.yaml$')
  } | sort
)

while IFS= read -r file; do
  if ! rg -q '^[[:space:]]+VOLSYNC_SCHEDULE:' "$file"; then
    echo "[err] ${file}: enabled VolSync component has no VOLSYNC_SCHEDULE" >&2
    errors=$((errors + 1))
  fi
done < <(
  rg -l '^[[:space:]]+-[[:space:]]+\.\./\.\./\.\./\.\./components/volsync$' \
    "${roots[@]}" --glob 'ks.yaml'
)

if [ "$count" -gt 60 ]; then
  echo "[err] ${count} VolSync sources exceed the 60 available three-hour slots" >&2
  errors=$((errors + 1))
fi

if [ "$errors" -gt 0 ]; then
  echo "[err] VolSync schedule validation failed with ${errors} error(s)" >&2
  exit 1
fi

echo "[ok] ${count} VolSync sources occupy unique three-hour slots"
