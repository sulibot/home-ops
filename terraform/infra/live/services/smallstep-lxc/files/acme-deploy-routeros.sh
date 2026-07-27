#!/usr/bin/env bash
# acme.sh deploy-hook: push a renewed cert into RouterOS's certificate
# store and (re)assign it to the www-ssl service. Installed at
# ~/.acme.sh/deploy/routeros.sh on pki01; invoked automatically by
# acme.sh's own renewal cron via:
#   acme.sh --deploy -d router.sulibot.com --deploy-hook routeros
#
# Config (env vars, not baked into the script):
#   ROUTEROS_HOST  - e.g. 10.30.0.254
#   ROUTEROS_USER  - e.g. admin
#   ROUTEROS_SSH_KEY - path to the dedicated deploy key (default below)
#
# See docs/tickets and Linear ENG-325 for context: RouterOS's native ACME
# client only supports HTTP-01 (needs port 80 open to the WAN), so this
# issues via Cloudflare DNS-01 on pki01 (same acme.sh instance already
# used for zot/minio/pki) and pushes the result in, rather than relying
# on RouterOS's own ACME client.

routeros_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  ROUTEROS_HOST="${ROUTEROS_HOST:-10.30.0.254}"
  ROUTEROS_USER="${ROUTEROS_USER:-admin}"
  ROUTEROS_SSH_KEY="${ROUTEROS_SSH_KEY:-/root/.ssh/routeros_deploy_ed25519}"
  SSH_OPTS="-i $ROUTEROS_SSH_KEY -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new"

  _info "routeros" "Deploying $_cdomain to RouterOS ($ROUTEROS_HOST)"

  REMOTE_CRT="acme-deploy-$_cdomain.crt"
  REMOTE_KEY="acme-deploy-$_cdomain.key"

  scp $SSH_OPTS "$_cfullchain" "$ROUTEROS_USER@$ROUTEROS_HOST:$REMOTE_CRT" || {
    _err "routeros" "scp of fullchain failed"
    return 1
  }
  scp $SSH_OPTS "$_ckey" "$ROUTEROS_USER@$ROUTEROS_HOST:$REMOTE_KEY" || {
    _err "routeros" "scp of key failed"
    return 1
  }

  # Import creates NEW certificate objects each time (RouterOS doesn't
  # overwrite in place), so capture the new cert's own id, reassign the
  # service to it, THEN clean up every older cert for this domain except
  # the one now in use - avoids ever leaving the service pointed at a
  # cert we're about to delete.
  ssh $SSH_OPTS "$ROUTEROS_USER@$ROUTEROS_HOST" \
    "/certificate import file-name=$REMOTE_CRT passphrase=\"\"; /certificate import file-name=$REMOTE_KEY passphrase=\"\"" \
    || { _err "routeros" "certificate import failed"; return 1; }

  # RouterOS prints multiple matches semicolon-separated on one line (not
  # newline-separated) - e.g. "*3;*7" if an old and newly-imported cert
  # both match common-name right after a real renewal. Take the last
  # (newest - RouterOS lists in creation order).
  NEW_CERT_IDS=$(ssh $SSH_OPTS "$ROUTEROS_USER@$ROUTEROS_HOST" \
    ":put [/certificate find where common-name=\"$_cdomain\"]" | tr -d '\r')
  NEW_CERT_ID=$(printf '%s' "$NEW_CERT_IDS" | awk -F';' '{print $NF}')
  if [ -z "$NEW_CERT_ID" ]; then
    _err "routeros" "could not find imported certificate by common-name=$_cdomain"
    return 1
  fi
  NEW_CERT_NAME=$(ssh $SSH_OPTS "$ROUTEROS_USER@$ROUTEROS_HOST" \
    ":put [/certificate get $NEW_CERT_ID name]" | tr -d '\r')

  ssh $SSH_OPTS "$ROUTEROS_USER@$ROUTEROS_HOST" \
    "/ip service set www-ssl certificate=\"$NEW_CERT_NAME\"" \
    || { _err "routeros" "failed to assign new cert to www-ssl"; return 1; }

  # Remove every OTHER cert for this common-name (i.e. every previous
  # import), now that www-ssl points at the new one.
  ssh $SSH_OPTS "$ROUTEROS_USER@$ROUTEROS_HOST" \
    "/certificate remove [find where common-name=\"$_cdomain\" and name!=\"$NEW_CERT_NAME\"]" 2>/dev/null

  ssh $SSH_OPTS "$ROUTEROS_USER@$ROUTEROS_HOST" "/file remove $REMOTE_CRT,$REMOTE_KEY" 2>/dev/null

  _info "routeros" "Deployed $_cdomain as RouterOS cert '$NEW_CERT_NAME', assigned to www-ssl"
  return 0
}
