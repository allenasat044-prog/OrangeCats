#!/bin/bash
set -eu

CONF="${HOSPITAL_CONF:-/usr/local/hospital/etc/hospital.conf}"
. "$CONF"

LOG="${HOSPITAL_LOG_DIR:-/var/log}/hospital-backup.log"
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"
}

if ! mount | grep -q " on $VOLUME "; then
  log "Volume not mounted, attaching $IMAGE"
  if ! hdiutil attach "$IMAGE" > /dev/null 2>&1; then
    log "ERROR: could not attach $IMAGE"
    exit 1
  fi
  diskutil enableOwnership "$VOLUME" > /dev/null 2>&1 || true
fi

mkdir -p "$BACKUP_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
NAME="hospital-data-$STAMP.tar.gz"
ARCHIVE="$BACKUP_DIR/$NAME"

# shellcheck disable=SC2086
COPYFILE_DISABLE=1 tar -czf "$ARCHIVE" -C "$VOLUME" $FOLDERS
(cd "$BACKUP_DIR" && shasum -a 256 "$NAME" > "$NAME.sha256")
log "Backup created: $ARCHIVE"

if "$BIN_DIR/hospital_verify.sh" "$ARCHIVE" > /dev/null; then
  log "Backup verified: $NAME"
else
  log "ERROR: verification failed for $NAME"
  exit 1
fi

ls -1t "$BACKUP_DIR"/hospital-data-*.tar.gz 2> /dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f "$old" "$old.sha256"
  log "Old backup removed: $(basename "$old")"
done
