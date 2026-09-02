#!/usr/bin/env bash
set -euo pipefail

helper="${1:?pass the built agent-github-exec path}"
request_id='req-1788299000-a1b2c3d4e5f6'
candidate_sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
base_sha='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
signature='dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'

dry_run() {
  AGENT_GITHUB_EXEC_DRY_RUN=1 bash "$helper" "$@"
}

dry_run push-verification-ref sulibot/onward "$candidate_sha" "$request_id" |
  jq -e --arg sha "$candidate_sha" --arg request "$request_id" '
    . == ["git","push","--force-with-lease","https://github.com/sulibot/onward.git",($sha + ":refs/heads/agents/verification/" + $request)]
  ' >/dev/null

dry_run delete-verification-ref sulibot/onward "$request_id" |
  jq -e --arg request "$request_id" '
    . == ["gh","api","--method","DELETE",("repos/sulibot/onward/git/refs/heads/agents/verification/" + $request)]
  ' >/dev/null

dry_run dispatch-verification sulibot/onward "$request_id" "$candidate_sha" "$base_sha" "$signature" |
  jq -e --arg request "$request_id" '
    index("-f") != null and
    index("event_type=onward-verification") != null and
    index("client_payload[profile_set]=affected+security") != null and
    index("client_payload[schema_version]=onward.verification.dispatch.v1") != null and
    index("client_payload[ref]=refs/heads/agents/verification/" + $request) != null
  ' >/dev/null

dry_run observe-run-download sulibot/onward 42 "$request_id" |
  jq -e --arg request "$request_id" '
    . == ["gh","run","download","42","--repo","sulibot/onward","--dir",("/var/lib/agent-github-exec/evidence/" + $request)]
  ' >/dev/null

if dry_run push-verification-ref attacker/repo "$candidate_sha" "$request_id" >/dev/null 2>&1; then
  echo "unapproved repository was accepted" >&2
  exit 1
fi

if dry_run push-verification-ref sulibot/onward main "$request_id" >/dev/null 2>&1; then
  echo "non-SHA candidate was accepted" >&2
  exit 1
fi

if dry_run cleanup-evidence '../../etc' >/dev/null 2>&1; then
  echo "unsafe evidence path was accepted" >&2
  exit 1
fi
