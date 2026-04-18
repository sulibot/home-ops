#!/usr/bin/env bash

set -euo pipefail

APP_HOST="filebrowser.sulibot.com"
AUTH_HOST="auth.sulibot.com"
APP_VIP=""
AUTH_VIP=""
MAX_HOPS=8

usage() {
  cat <<'EOF'
Usage: ./scripts/validate-internal-auth-path.sh [options]

Validate whether a LAN client stays on the internal gateway path or leaks to
Cloudflare Access during an Authentik-backed login flow.

Options:
  --app-host HOST      App hostname to test (default: filebrowser.sulibot.com)
  --auth-host HOST     Authentik hostname to test (default: auth.sulibot.com)
  --app-vip IP         Local VIP to pin for the app host (default: first resolved IPv4)
  --auth-vip IP        Local VIP to pin for the auth host (default: first resolved IPv4)
  --max-hops N         Maximum redirects to follow per trace (default: 8)
  -h, --help           Show this help

Examples:
  ./scripts/validate-internal-auth-path.sh
  ./scripts/validate-internal-auth-path.sh --app-host paperless.sulibot.com --app-vip 10.101.250.12 --auth-vip 10.101.250.12
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-host)
      APP_HOST="$2"
      shift 2
      ;;
    --auth-host)
      AUTH_HOST="$2"
      shift 2
      ;;
    --app-vip)
      APP_VIP="$2"
      shift 2
      ;;
    --auth-vip)
      AUTH_VIP="$2"
      shift 2
      ;;
    --max-hops)
      MAX_HOPS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd curl

header() {
  printf '\n== %s ==\n' "$1"
}

resolve_host() {
  local host="$1"

  if command -v dig >/dev/null 2>&1; then
    dig +short "$host" A "$host" AAAA | sed '/^$/d'
    return
  fi

  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 2>/dev/null | awk '/^Address: / {print $2}'
    return
  fi

  if command -v getent >/dev/null 2>&1; then
    getent ahosts "$host" | awk '{print $1}' | sort -u
    return
  fi

  echo "No supported DNS lookup tool found (dig/nslookup/getent)." >&2
  return 1
}

first_ipv4_for_host() {
  local host="$1"
  resolve_host "$host" | awk '/^[0-9]+\./ {print; exit}'
}

extract_host() {
  printf '%s\n' "$1" | sed -E 's#^[a-zA-Z]+://([^/@]+@)?([^/:?#]+).*#\2#'
}

extract_scheme() {
  printf '%s\n' "$1" | sed -E 's#^([a-zA-Z]+)://.*#\1#'
}

absolutize_location() {
  local current_url="$1"
  local location="$2"
  local scheme host

  if [[ "$location" =~ ^https?:// ]]; then
    printf '%s\n' "$location"
    return
  fi

  scheme="$(extract_scheme "$current_url")"
  host="$(extract_host "$current_url")"

  if [[ "$location" == /* ]]; then
    printf '%s://%s%s\n' "$scheme" "$host" "$location"
    return
  fi

  printf '%s\n' "$location"
}

resolve_args_for_url() {
  local url="$1"
  local host

  host="$(extract_host "$url")"

  if [[ "$host" == "$APP_HOST" && -n "$APP_VIP" ]]; then
    printf '%s\n' "--resolve" "${host}:443:${APP_VIP}"
    return
  fi

  if [[ "$host" == "$AUTH_HOST" && -n "$AUTH_VIP" ]]; then
    printf '%s\n' "--resolve" "${host}:443:${AUTH_VIP}"
    return
  fi
}

curl_headers() {
  local url="$1"
  local outfile="$2"
  shift 2

  curl -ksS -o /dev/null -D "$outfile" "$@" "$url"
}

trace_redirects() {
  local label="$1"
  local start_url="$2"
  local force_local="$3"
  local url next_url
  local hop=1
  local tmp
  local status location server host
  local -a extra_args=()

  url="$start_url"

  header "$label"

  while (( hop <= MAX_HOPS )); do
    tmp="$(mktemp)"
    host="$(extract_host "$url")"
    extra_args=()

    if [[ "$force_local" == "yes" ]]; then
      while IFS= read -r arg; do
        extra_args+=("$arg")
      done < <(resolve_args_for_url "$url")
    fi

    if ((${#extra_args[@]} > 0)); then
      if ! curl_headers "$url" "$tmp" "${extra_args[@]}"; then
        echo "hop $hop: request failed for $url"
        rm -f "$tmp"
        return 1
      fi
    else
      if ! curl_headers "$url" "$tmp"; then
        echo "hop $hop: request failed for $url"
        rm -f "$tmp"
        return 1
      fi
    fi

    status="$(awk 'toupper($0) ~ /^HTTP\// {code=$2} END {print code}' "$tmp")"
    location="$(awk 'BEGIN {IGNORECASE=1} /^Location:/ {$1=""; sub(/^ /,""); loc=$0} END {print loc}' "$tmp" | tr -d '\r')"
    server="$(awk 'BEGIN {IGNORECASE=1} /^Server:/ {$1=""; sub(/^ /,""); value=$0} END {print value}' "$tmp" | tr -d '\r')"

    printf 'hop %d\n' "$hop"
    printf '  url: %s\n' "$url"
    printf '  host: %s\n' "$host"
    printf '  status: %s\n' "${status:-unknown}"
    if [[ -n "$server" ]]; then
      printf '  server: %s\n' "$server"
    fi
    if [[ "$force_local" == "yes" ]]; then
      if [[ "$host" == "$APP_HOST" ]]; then
        printf '  pinned-vip: %s\n' "$APP_VIP"
      elif [[ "$host" == "$AUTH_HOST" ]]; then
        printf '  pinned-vip: %s\n' "$AUTH_VIP"
      fi
    fi

    rm -f "$tmp"

    if [[ -z "$location" ]]; then
      echo "  next: none"
      break
    fi

    next_url="$(absolutize_location "$url" "$location")"
    printf '  next: %s\n' "$next_url"

    if [[ "$next_url" == *"cloudflareaccess.com"* ]]; then
      echo "  leak-detected: redirect reached Cloudflare Access"
      break
    fi

    url="$next_url"
    hop=$((hop + 1))
  done
}

probe_local_vip() {
  local host="$1"
  local vip="$2"
  local tmp status location

  if [[ -z "$vip" ]]; then
    echo "${host} has no IPv4 VIP to probe"
    return
  fi

  tmp="$(mktemp)"
  curl -ksS -o /dev/null -D "$tmp" --resolve "${host}:443:${vip}" "https://${host}"
  status="$(awk 'toupper($0) ~ /^HTTP\// {code=$2} END {print code}' "$tmp")"
  location="$(awk 'BEGIN {IGNORECASE=1} /^Location:/ {$1=""; sub(/^ /,""); loc=$0} END {print loc}' "$tmp" | tr -d '\r')"

  printf '%s pinned to %s\n' "$host" "$vip"
  printf '  status: %s\n' "${status:-unknown}"
  if [[ -n "$location" ]]; then
    printf '  location: %s\n' "$location"
  fi

  rm -f "$tmp"
}

repo_hint() {
  if [[ ! -d ".git" && ! -f "manifest.yaml" ]]; then
    return
  fi

  header "Repo Hints"

  if command -v rg >/dev/null 2>&1; then
    rg -n "issuerUrl:|hostnames:|parentRefs:|name: gateway-" \
      kubernetes/apps/tier-2-applications/filebrowser/app/externalsecret-oidc.yaml \
      kubernetes/apps/tier-2-applications/filebrowser/app/helmrelease.yaml \
      kubernetes/apps/tier-2-applications/authentik/app/httproute.yaml \
      2>/dev/null || true
  else
    echo "ripgrep not installed; skipping manifest hints"
  fi
}

if [[ -z "$APP_VIP" ]]; then
  APP_VIP="$(first_ipv4_for_host "$APP_HOST" || true)"
fi

if [[ -z "$AUTH_VIP" ]]; then
  AUTH_VIP="$(first_ipv4_for_host "$AUTH_HOST" || true)"
fi

header "DNS Resolution"
echo "$APP_HOST"
resolve_host "$APP_HOST" | sed 's/^/  /'
echo "$AUTH_HOST"
resolve_host "$AUTH_HOST" | sed 's/^/  /'

header "Pinned Local VIP Probes"
probe_local_vip "$APP_HOST" "$APP_VIP"
probe_local_vip "$AUTH_HOST" "$AUTH_VIP"

trace_redirects "Normal Client Resolution" "https://${APP_HOST}" "no"
trace_redirects "Forced Local VIP Resolution" "https://${APP_HOST}" "yes"

repo_hint

header "Interpretation"
cat <<EOF
- If normal resolution reaches cloudflareaccess.com but forced local VIP does not, the client path is leaking to public DNS or a browser-specific resolver.
- If both normal and forced local traces reach cloudflareaccess.com, the app/auth redirect chain itself is still pointing at a Cloudflare-gated path.
- If ${APP_HOST} resolves local but ${AUTH_HOST} does not, split-DNS coverage is incomplete for Authentik.
EOF
