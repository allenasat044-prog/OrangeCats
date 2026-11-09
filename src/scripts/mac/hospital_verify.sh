#!/bin/bash
set -eu

CONF="${HOSPITAL_CONF:-/usr/local/hospital/etc/hospital.conf}"
. "$CONF"

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ]; then
  ARCHIVE="$(ls -1t "$BACKUP_DIR"/hospital-data-*.tar.gz 2> /dev/null | head -n 1 || true)"
fi

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  echo "No backup found." >&2
  exit 1
fi

cd "$(dirname "$ARCHIVE")"
NAME="$(basename "$ARCHIVE")"

shasum -a 256 -c "$NAME.sha256"
tar -tzf "$NAME" > /dev/null
echo "Archive readable: $NAME"
echo "Files in archive: $(tar -tzf "$NAME" | grep -vc '/$' || true)"
