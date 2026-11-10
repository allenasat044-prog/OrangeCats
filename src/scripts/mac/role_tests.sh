#!/bin/bash
set -u

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

VOLUME="${VOLUME:-/Volumes/hospital}"
FOLDERS=(patient-records nursing-notes billing announcements)

EXPECT=(
  "dr_asha|rw|r|-|r"
  "dr_ravi|rw|r|-|r"
  "nurse_meera|r|rw|-|r"
  "nurse_john|r|rw|-|r"
  "admin_priya|-|-|rw|rw"
  "admin_kiran|-|-|rw|rw"
)

access() {
  user="$1"
  dir="$2"
  can_read=0
  can_write=0
  if sudo -u "$user" ls "$dir" > /dev/null 2>&1; then
    can_read=1
  fi
  probe="$dir/.role_test_$user"
  if sudo -u "$user" touch "$probe" > /dev/null 2>&1; then
    can_write=1
    sudo -u "$user" rm -f "$probe" > /dev/null 2>&1 || true
  fi
  rm -f "$probe"
  if [ "$can_read" = 1 ] && [ "$can_write" = 1 ]; then
    echo "rw"
  elif [ "$can_read" = 1 ]; then
    echo "r"
  elif [ "$can_write" = 0 ]; then
    echo "-"
  else
    echo "?"
  fi
}

BAD=0
printf '%-13s' "user"
for f in "${FOLDERS[@]}"; do
  printf '%-18s' "$f"
done
echo

for def in "${EXPECT[@]}"; do
  IFS='|' read -r user e1 e2 e3 e4 <<< "$def"
  expected=("$e1" "$e2" "$e3" "$e4")
  printf '%-13s' "$user"
  i=0
  for f in "${FOLDERS[@]}"; do
    actual="$(access "$user" "$VOLUME/$f")"
    if [ "$actual" = "${expected[$i]}" ]; then
      printf '%-18s' "$actual ok"
    else
      printf '%-18s' "$actual WRONG"
      BAD=$((BAD + 1))
    fi
    i=$((i + 1))
  done
  echo
done

echo
if [ "$BAD" -eq 0 ]; then
  echo "All role checks passed."
else
  echo "$BAD role check(s) failed."
  exit 1
fi
