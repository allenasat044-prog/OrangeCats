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
IMAGE="$IMAGE_DIR/hospital.sparseimage"

RW="list,search,add_file,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,file_inherit,directory_inherit"
R="list,search,readattr,readextattr,file_inherit,directory_inherit"

ROLE_GROUPS=(doctors nurses hosp_admin)

FOLDERS=(
  "patient-records|rw|r|none"
  "nursing-notes|r|rw|none"
  "billing|none|none|rw"
  "announcements|r|r|rw"
)

mkdir -p "$IMAGE_DIR"

if [ -f "$IMAGE" ]; then
  echo "Disk image exists: $IMAGE"
else
  hdiutil create -size 2g -type SPARSE -fs APFS -volname hospital "$IMAGE_DIR/hospital"
  echo "Disk image created: $IMAGE"
fi

if mount | grep -q " on $VOLUME "; then
  echo "Already mounted: $VOLUME"
else
  hdiutil attach "$IMAGE"
fi

diskutil enableOwnership "$VOLUME"
chown root:wheel "$VOLUME"
chmod 755 "$VOLUME"

for def in "${FOLDERS[@]}"; do
  IFS='|' read -r folder d n a <<< "$def"
  levels=("$d" "$n" "$a")
  dir="$VOLUME/$folder"
  mkdir -p "$dir"
  chown root:wheel "$dir"
  chmod 700 "$dir"
  chmod -N "$dir"
  i=0
  for g in "${ROLE_GROUPS[@]}"; do
    case "${levels[$i]}" in
      rw) chmod +a "group:$g allow $RW" "$dir" ;;
      r) chmod +a "group:$g allow $R" "$dir" ;;
    esac
    i=$((i + 1))
  done
  echo "Folder ready: $dir"
done

echo
ls -led "$VOLUME"/*
