#!/usr/bin/env bash
set -euo pipefail

export RESTIC_REPOSITORY=/var/backups/kanidm/restic
export RESTIC_PASSWORD_FILE=/etc/kanidm/restic-password

mkdir -p /var/backups/kanidm/snapshots

if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
  umask 077
  openssl rand -base64 48 >"$RESTIC_PASSWORD_FILE"
fi

if [ ! -f "$RESTIC_REPOSITORY/config" ]; then
  restic init
fi

# Fail closed if the password no longer opens an existing repository. Calling
# `restic init` on every connection error masks credential drift and produces
# an endless hourly failure loop.
restic snapshots >/dev/null

snapshot="/var/backups/kanidm/snapshots/kanidm-$(date -u +%Y%m%dT%H%M%SZ).db"
if [ -f /var/lib/kanidm/kanidm.db ]; then
  sqlite3 /var/lib/kanidm/kanidm.db ".backup '$snapshot'"
  test "$(sqlite3 "$snapshot" "PRAGMA integrity_check;")" = "ok"
fi

restic backup \
  /etc/kanidm \
  /var/lib/kanidm \
  /var/backups/kanidm/snapshots \
  --tag kanidm

restic forget \
  --prune \
  --keep-hourly 24 \
  --keep-daily 3 \
  --keep-weekly 4 \
  --keep-monthly 3
