#!/bin/bash
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

HOME_ROOT="${HOME_ROOT:-/Users}"

USER_DEFS=(
  "dr_asha|801"
  "dr_ravi|802"
  "nurse_meera|803"
  "nurse_john|804"
  "admin_priya|805"
  "admin_kiran|806"
)

GROUP_DEFS=(
  "doctors|801"
  "nurses|802"
  "hosp_admin|803"
)

for def in "${USER_DEFS[@]}"; do
  IFS='|' read -r name uid <<< "$def"
  if dscl . -read "/Users/$name" > /dev/null 2>&1; then
    actual="$(dscl . -read "/Users/$name" UniqueID | awk '{ print $2 }')"
    if [ "$actual" = "$uid" ]; then
      dscl . -delete "/Users/$name"
      rm -rf "${HOME_ROOT:?}/$name"
      echo "User removed: $name"
    else
      echo "Skipped $name: UID $actual is not the expected $uid." >&2
    fi
  else
    echo "User not found: $name"
  fi
done

for def in "${GROUP_DEFS[@]}"; do
  IFS='|' read -r name gid <<< "$def"
  if dscl . -read "/Groups/$name" > /dev/null 2>&1; then
    actual="$(dscl . -read "/Groups/$name" PrimaryGroupID | awk '{ print $2 }')"
    if [ "$actual" = "$gid" ]; then
      dseditgroup -o delete -n . "$name"
      echo "Group removed: $name"
    else
      echo "Skipped $name: GID $actual is not the expected $gid." >&2
    fi
  else
    echo "Group not found: $name"
  fi
done
