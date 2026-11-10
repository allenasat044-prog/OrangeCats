#!/bin/bash
set -u

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

VOLUME="${VOLUME:-/Volumes/hospital}"
BACKUP_DIR="${BACKUP_DIR:-/Users/Shared/hospital-backups}"
FAILS=0

pass() {
  echo "PASS: $*"
}

fail() {
  echo "FAIL: $*"
  FAILS=$((FAILS + 1))
}

if diskutil info "$VOLUME" 2> /dev/null | grep -q 'Owners: *Enabled'; then
  pass "ownership is enabled on $VOLUME"
else
  fail "ownership is not enabled on $VOLUME"
fi

EXPECT=(
  "patient-records|2"
  "nursing-notes|2"
  "billing|1"
  "announcements|3"
)

for def in "${EXPECT[@]}"; do
  IFS='|' read -r folder count <<< "$def"
  dir="$VOLUME/$folder"
  meta="$(stat -f '%Sp %Su:%Sg' "$dir" 2> /dev/null || true)"
  if [ "$meta" = "drwx------ root:wheel" ]; then
    pass "$folder is drwx------ root:wheel"
  else
    fail "$folder is '$meta'"
  fi
  acl="$(ls -led "$dir" 2> /dev/null | grep -c ' allow ' || true)"
  if [ "$acl" = "$count" ]; then
    pass "$folder has $count ACL entries"
  else
    fail "$folder has $acl ACL entries, expected $count"
  fi
done

writable="$(find "$VOLUME" -perm -0002 2> /dev/null | wc -l | tr -d ' ')"
if [ "$writable" = "0" ]; then
  pass "no world-writable items on $VOLUME"
else
  fail "$writable world-writable items on $VOLUME"
fi

for u in dr_asha dr_ravi nurse_meera nurse_john admin_priya admin_kiran; do
  if dseditgroup -o checkmember -m "$u" admin 2>&1 | grep -q '^yes'; then
    fail "$u is a macOS administrator"
  else
    pass "$u is a standard user"
  fi
done

meta="$(stat -f '%Sp %Su:%Sg' "$BACKUP_DIR" 2> /dev/null || true)"
if [ "$meta" = "drwx------ root:wheel" ]; then
  pass "backup folder is drwx------ root:wheel"
else
  fail "backup folder is '$meta'"
fi

if /usr/sbin/sshd -T 2> /dev/null | grep -q '^permitrootlogin no'; then
  pass "SSH root login is disabled"
else
  fail "SSH root login is not disabled"
fi

if pfctl -s info 2> /dev/null | grep -q '^Status: Enabled' && pfctl -a com.hospital -s rules 2> /dev/null | grep -q block; then
  pass "firewall is enabled with the hospital rules"
else
  fail "firewall is not enabled with the hospital rules"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$FAILS check(s) failed."
  exit 1
fi
