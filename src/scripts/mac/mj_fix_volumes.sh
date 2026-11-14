#!/bin/bash
# MJ Fix - Volumes (macOS): ONE VOLUME PER ROLE FOLDER (macOS has no LVM: each is its own disk image).
#   patient-records (doctors) | nursing-notes (nurses) | billing (hosp_admin) | announcements (shared)
# Needs the existing build first (setup_storage.sh mounted at /Volumes/hospital).
# Usage: sudo bash mj_fix_volumes.sh create|status|grow FOLDER SIZE|isolation [FOLDER]|mount-all|teardown
#        DRY_RUN=1 sudo -E bash ... prints the commands without running them.
set -u
if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo from your normal account." >&2; exit 1; fi

VOLUME="${VOLUME:-/Volumes/hospital}"
FOLDERS="patient-records:1g nursing-notes:1g billing:500m announcements:250m"
OWNER_HOME="$(dscl . -read "/Users/${SUDO_USER:-root}" NFSHomeDirectory 2> /dev/null | awk '{ print $2 }')"
IMAGE_DIR="${IMAGE_DIR:-${OWNER_HOME:-$HOME}/hospital-storage/roles}"

run() { if [ "${DRY_RUN:-0}" = 1 ]; then echo "+ $*"; else "$@"; fi; }
is_mounted() { mount | grep -q " on $1 ("; }
img_of() { echo "$IMAGE_DIR/$1.sparseimage"; }

do_create() {
  if [ "${DRY_RUN:-0}" != 1 ] && ! is_mounted "$VOLUME"; then echo "$VOLUME is not mounted. Run setup_storage.sh first." >&2; exit 1; fi
  run mkdir -p "$IMAGE_DIR"
  for pair in $FOLDERS; do
    f="${pair%%:*}"; size="${pair##*:}"; img="$(img_of "$f")"; dir="$VOLUME/$f"
    echo "--- $f  ($size)"
    if [ ! -f "$img" ]; then run hdiutil create -size "$size" -type SPARSE -fs APFS -volname "hospital-$f" "${img%.sparseimage}"; fi
    run mkdir -p "$dir"
    if is_mounted "$dir"; then echo "already mounted: $dir"; continue; fi
    tmp=""
    if [ -n "$(ls -A "$dir" 2> /dev/null)" ]; then   # mounting hides existing files: save them first
      tmp="/tmp/mj_migrate_$f"; run rm -rf "$tmp"; run ditto "$dir" "$tmp"
      echo "existing data saved, will be restored into the new volume"
    fi
    run hdiutil attach -owners on -mountpoint "$dir" "$img"
    run diskutil enableOwnership "$dir"
    if [ -n "$tmp" ]; then run ditto "$tmp" "$dir"; run rm -rf "$tmp"; fi
  done
  echo; echo "Done. Now apply permissions:  sudo bash mj_fix_stage1_permissions.sh baseline"
}

do_status() {
  printf '%-18s %-8s %-8s %-6s\n' folder size used use%
  for pair in $FOLDERS; do
    f="${pair%%:*}"; dir="$VOLUME/$f"
    if is_mounted "$dir"; then df -h "$dir" | tail -n 1 | awk -v f="$f" '{ printf "%-18s %-8s %-8s %-6s\n", f, $2, $3, $5 }'
    else printf '%-18s %s\n' "$f" "(not a separate volume)"; fi
  done
}

do_grow() { # grow FOLDER NEWSIZE  e.g. grow billing 1g
  f="${1:?usage: grow FOLDER NEWSIZE}"; size="${2:?usage: grow FOLDER NEWSIZE}"; dir="$VOLUME/$f"
  run hdiutil detach "$dir"
  run hdiutil resize -size "$size" "$(img_of "$f")"
  run hdiutil attach -owners on -mountpoint "$dir" "$(img_of "$f")"
  run diskutil enableOwnership "$dir"
  do_status
}

do_isolation() { # fill ONE volume, show the others are unaffected
  f="${1:-billing}"; dir="$VOLUME/$f"
  is_mounted "$dir" || { echo "$f is not a separate volume. Run create first." >&2; exit 1; }
  echo "Filling '$f' completely..."
  dd if=/dev/zero of="$dir/.mj_fill" bs=1m 2> /dev/null
  do_status
  echo; echo "'$f' is FULL, every other role's volume still has its own space."
  rm -f "$dir/.mj_fill"; echo "Cleaned up the test file."
}

do_mount_all() {
  for pair in $FOLDERS; do
    f="${pair%%:*}"; dir="$VOLUME/$f"
    if ! is_mounted "$dir"; then run hdiutil attach -owners on -mountpoint "$dir" "$(img_of "$f")"; run diskutil enableOwnership "$dir"; fi
  done
  do_status
}

do_teardown() {
  printf "This DELETES the role volumes and their data. Type yes: "; read -r a || a=""
  if [ "$a" != yes ]; then echo cancelled; exit 0; fi
  for pair in $FOLDERS; do
    f="${pair%%:*}"; if is_mounted "$VOLUME/$f"; then run hdiutil detach "$VOLUME/$f"; fi
    run rm -f "$(img_of "$f")"
  done
}

case "${1:-status}" in
  create) do_create ;; status) do_status ;; grow) do_grow "${2:-}" "${3:-}" ;;
  isolation) do_isolation "${2:-billing}" ;; mount-all) do_mount_all ;; teardown) do_teardown ;;
  *) echo "Usage: sudo bash $0 create|status|grow FOLDER SIZE|isolation [FOLDER]|mount-all|teardown"; exit 1 ;;
esac
