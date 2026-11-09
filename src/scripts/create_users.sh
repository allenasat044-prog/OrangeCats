#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

declare -A MEMBERS=(
  [doctors]="dr_asha dr_ravi"
  [nurses]="nurse_meera nurse_john"
  [admin]="admin_priya admin_kiran"
)
ORDER=(doctors nurses admin)

read -rsp "Password for the sample users (minimum 8 characters): " PASS
echo
read -rsp "Confirm password: " PASS2
echo

if [[ "$PASS" != "$PASS2" ]]; then
  echo "Passwords do not match." >&2
  exit 1
fi
if [[ ${#PASS} -lt 8 ]]; then
  echo "Password must be at least 8 characters." >&2
  exit 1
fi

for group in "${ORDER[@]}"; do
  if getent group "$group" > /dev/null; then
    echo "Group exists: $group"
  else
    groupadd "$group"
    echo "Group created: $group"
  fi

  for u in ${MEMBERS[$group]}; do
    if id "$u" > /dev/null 2>&1; then
      usermod -aG "$group" "$u"
      echo "User exists, group ensured: $u -> $group"
    else
      useradd -m -s /bin/bash -G "$group" -c "Hospital $group user" "$u"
      echo "User created: $u -> $group"
    fi
    echo "$u:$PASS" | chpasswd
    chage -M 90 -W 7 "$u"
    chmod 700 "/home/$u"
  done
done

echo
echo "Group membership:"
getent group "${ORDER[@]}"
