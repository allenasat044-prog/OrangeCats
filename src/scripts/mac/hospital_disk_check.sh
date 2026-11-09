#!/bin/bash
set -eu

CONF="${HOSPITAL_CONF:-/usr/local/hospital/etc/hospital.conf}"
. "$CONF"

LIMIT="${1:-$THRESHOLD}"
LOG="${HOSPITAL_LOG_DIR:-/var/log}/hospital-disk.log"
STATUS=0

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"
}

check() {
  label="$1"
  path="$2"
  if [ ! -d "$path" ]; then
    log "WARNING: $label not available at $path"
    STATUS=1
    return
  fi
  used="$(df -k "$path" | awk 'NR == 2 { gsub("%", "", $5); print $5 }')"
  if [ "$used" -ge "$LIMIT" ]; then
    log "WARNING: $label is ${used}% full (limit ${LIMIT}%)"
    STATUS=1
  else
    log "OK: $label is ${used}% full (limit ${LIMIT}%)"
  fi
}

check "hospital volume" "$VOLUME"
check "backup storage" "$BACKUP_DIR"

exit "$STATUS"
