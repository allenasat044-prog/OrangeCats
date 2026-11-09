#!/bin/bash
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [ -z "${SUDO_USER:-}" ]; then
  echo "Run this script with sudo from your normal account." >&2
  exit 1
fi

VOLUME="${VOLUME:-/Volumes/hospital}"
OWNER_HOME="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory | awk '{ print $2 }')"
IMAGE_DIR="$OWNER_HOME/hospital-storage"

if mount | grep -q " on $VOLUME "; then
  hdiutil detach "$VOLUME"
  echo "Detached: $VOLUME"
else
  echo "Not mounted: $VOLUME"
fi

rm -rf "${IMAGE_DIR:?}"
echo "Removed: $IMAGE_DIR"
