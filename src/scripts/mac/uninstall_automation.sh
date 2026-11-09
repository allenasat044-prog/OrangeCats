#!/bin/bash
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

PREFIX="${PREFIX:-/usr/local/hospital}"
LAUNCHD_DIR="${LAUNCHD_DIR:-/Library/LaunchDaemons}"

for label in com.hospital.backup com.hospital.diskcheck; do
  launchctl bootout "system/$label" > /dev/null 2>&1 || true
  rm -f "$LAUNCHD_DIR/$label.plist"
  echo "Unscheduled: $label"
done

rm -rf "${PREFIX:?}"
echo "Removed: $PREFIX"
echo "Backups in /Users/Shared/hospital-backups were kept. Delete that folder yourself if you no longer need them."
