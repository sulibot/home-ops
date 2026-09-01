#!/usr/bin/env bash
set -euo pipefail

intent="${1:-}"
shift || true

request_pattern='^req-[0-9]{10}-[0-9a-f]{12}$'
sha_pattern='^[0-9a-f]{40}$'
run_id_pattern='^[0-9]+$'
repository_pattern='^sulibot/onward$'
evidence_root='/var/lib/agent-github-exec/evidence'

die() {
  echo "$1" >&2
  exit 2
}

require_count() {
  expected="$1"
  shift
  [ "$#" -eq "$expected" ] || die "invalid argument count for $intent"
}

validate_repository() {
  [[ "$1" =~ $repository_pattern ]] || die "repository is not approved"
}

validate_request_id() {
  [[ "$1" =~ $request_pattern ]] || die "invalid verification request ID"
}

validate_sha() {
  [[ "$1" =~ $sha_pattern ]] || die "invalid full commit SHA"
}

validate_run_id() {
  [[ "$1" =~ $run_id_pattern ]] || die "invalid workflow run ID"
}

permission=''
command=()
evidence_directory=''

case "$intent" in
  push-verification-ref)
    require_count 3 "$@"
    repository="$1"
    candidate_sha="$2"
    request_id="$3"
    validate_repository "$repository"
    validate_sha "$candidate_sha"
    validate_request_id "$request_id"
    permission='ref-write'
    command=(git push --force-with-lease "https://github.com/$repository.git" "$candidate_sha:refs/heads/agents/verification/$request_id")
    ;;
  delete-verification-ref)
    require_count 2 "$@"
    repository="$1"
    request_id="$2"
    validate_repository "$repository"
    validate_request_id "$request_id"
    permission='ref-write'
    command=(git push "https://github.com/$repository.git" ":refs/heads/agents/verification/$request_id")
    ;;
  dispatch-verification)
    require_count 5 "$@"
    repository="$1"
    request_id="$2"
    candidate_sha="$3"
    base_sha="$4"
    signature="$5"
    validate_repository "$repository"
    validate_request_id "$request_id"
    validate_sha "$candidate_sha"
    validate_sha "$base_sha"
    [[ "$signature" =~ ^[0-9a-f]{64}$ ]] || die "invalid dispatch signature"
    permission='ref-write'
    ref="refs/heads/agents/verification/$request_id"
    command=(
      gh api --method POST "repos/$repository/dispatches"
      -f event_type=onward-verification
      -f "client_payload[request_id]=$request_id"
      -f "client_payload[candidate_sha]=$candidate_sha"
      -f "client_payload[base_sha]=$base_sha"
      -f 'client_payload[profile_set]=affected+security'
      -f "client_payload[ref]=$ref"
      -f 'client_payload[schema_version]=onward.verification.dispatch.v1'
      -f "client_payload[signature]=$signature"
    )
    ;;
  observe-run-list)
    require_count 2 "$@"
    repository="$1"
    request_id="$2"
    validate_repository "$repository"
    validate_request_id "$request_id"
    permission='observe'
    command=(
      gh run list --repo "$repository" --workflow burst-verification.yml
      --event repository_dispatch --limit 50
      --json 'databaseId,displayTitle,headSha,status,conclusion,url'
    )
    ;;
  observe-run-watch)
    require_count 2 "$@"
    repository="$1"
    run_id="$2"
    validate_repository "$repository"
    validate_run_id "$run_id"
    permission='observe'
    command=(gh run watch "$run_id" --repo "$repository" --exit-status)
    ;;
  observe-run-download)
    require_count 3 "$@"
    repository="$1"
    run_id="$2"
    request_id="$3"
    validate_repository "$repository"
    validate_run_id "$run_id"
    validate_request_id "$request_id"
    permission='observe'
    evidence_directory="$evidence_root/$request_id"
    command=(gh run download "$run_id" --repo "$repository" --dir "$evidence_directory")
    ;;
  cleanup-evidence)
    require_count 1 "$@"
    request_id="$1"
    validate_request_id "$request_id"
    evidence_directory="$evidence_root/$request_id"
    command=(rm -rf -- "$evidence_directory")
    ;;
  *)
    die "unsupported GitHub helper intent"
    ;;
esac

if [ "${AGENT_GITHUB_EXEC_DRY_RUN:-}" = 1 ]; then
  jq -cn --args '$ARGS.positional' -- "${command[@]}"
  exit 0
fi

if [ "$intent" = cleanup-evidence ]; then
  exec "${command[@]}"
fi

secret="$(agent-github-secret)"
app_id="$(jq -er '.app_id' <<<"$secret")"
installation_id="$(jq -er '.installation_id' <<<"$secret")"
key_file="$(mktemp)"
trap 'rm -f "$key_file"' EXIT
jq -er '.private_key' <<<"$secret" >"$key_file"
chmod 0600 "$key_file"
base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)"
payload="$(jq -cn --argjson iat "$((now - 60))" --argjson exp "$((now + 540))" --arg iss "$app_id" '{iat:$iat,exp:$exp,iss:$iss}' | base64url)"
unsigned="$header.$payload"
signature="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$key_file" -binary | base64url)"
jwt="$unsigned.$signature"

case "$permission" in
  ref-write) permissions='{"contents":"write"}' ;;
  observe) permissions='{"actions":"read","checks":"read","contents":"read"}' ;;
  *) die "internal permission error" ;;
esac

token="$(curl --silent --show-error --fail-with-body --request POST \
  --header "Authorization: Bearer $jwt" \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  --data "{\"permissions\":$permissions}" \
  "https://api.github.com/app/installations/$installation_id/access_tokens" | jq -er '.token')"
rm -f "$key_file"
trap - EXIT

if [ "$intent" = observe-run-download ]; then
  mkdir "$evidence_directory"
  chown agent:agent "$evidence_directory"
fi

if [ "$intent" = push-verification-ref ] || [ "$intent" = delete-verification-ref ]; then
  basic_auth="$(printf 'x-access-token:%s' "$token" | base64 -w0)"
  exec runuser -u agent -- env \
    HOME=/home/agent \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=http.https://github.com/.extraheader \
    GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $basic_auth" \
    "${command[@]}"
fi

if [ "$intent" = observe-run-download ]; then
  runuser -u agent -- env HOME=/home/agent GH_TOKEN="$token" GITHUB_TOKEN="$token" "${command[@]}"
  printf '%s\n' "$evidence_directory"
  exit 0
fi

exec runuser -u agent -- env HOME=/home/agent GH_TOKEN="$token" GITHUB_TOKEN="$token" "${command[@]}"
