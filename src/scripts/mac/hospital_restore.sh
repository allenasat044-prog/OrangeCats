#!/bin/bash
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

PREFIX="${PREFIX:-/usr/local/hospital}"
CONF="${HOSPITAL_CONF:-$PREFIX/etc/hospital.conf}"
. "$CONF"

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${HOSPITAL_LOG_DIR:-/var/log}/hospital-restore.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"
}

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ]; then
  ARCHIVE="$(ls -1t "$BACKUP_DIR"/hospital-data-*.tar.gz 2> /dev/null | head -n 1 || true)"
fi

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  log "ERROR: no backup found in $BACKUP_DIR"
  exit 1
fi

if ! "$PREFIX/bin/hospital_verify.sh" "$ARCHIVE" > /dev/null; then
  log "ERROR: backup failed verification, nothing was restored: $ARCHIVE"
  exit 1
fi
log "Backup verified: $(basename "$ARCHIVE")"

if ! mount | grep -q " on $VOLUME "; then
  log "Volume not mounted, mounting it first"
fi
bash "$DIR/setup_storage.sh" > /dev/null
log "Volume ready: $VOLUME"

tar -xzf "$ARCHIVE" -C "$VOLUME"
log "Files restored from $(basename "$ARCHIVE")"

bash "$DIR/setup_storage.sh" > /dev/null
log "Folder permissions and ACLs re-applied"

for folder in $FOLDERS; do
  count="$(find "$VOLUME/$folder" -type f 2> /dev/null | wc -l | tr -d ' ')"
  log "Restored $folder: $count files"
done
