#!/bin/bash
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

HOME_ROOT="${HOME_ROOT:-/Users}"

GROUP_DEFS=(
  "doctors|801"
  "nurses|802"
  "hosp_admin|803"
)

USER_DEFS=(
  "dr_asha|801|doctors|Dr Asha"
  "dr_ravi|802|doctors|Dr Ravi"
  "nurse_meera|803|nurses|Nurse Meera"
  "nurse_john|804|nurses|Nurse John"
  "admin_priya|805|hosp_admin|Admin Priya"
  "admin_kiran|806|hosp_admin|Admin Kiran"
)

printf "Password for the sample users (minimum 8 characters): "
read -rs PASS
echo
printf "Confirm password: "
read -rs PASS2
echo

if [ "$PASS" != "$PASS2" ]; then
  echo "Passwords do not match." >&2
  exit 1
fi
if [ "${#PASS}" -lt 8 ]; then
  echo "Password must be at least 8 characters." >&2
  exit 1
fi

for def in "${GROUP_DEFS[@]}"; do
  IFS='|' read -r name gid <<< "$def"
  if dscl . -read "/Groups/$name" > /dev/null 2>&1; then
    echo "Group exists: $name"
  else
    if dscl . -list /Groups PrimaryGroupID | awk -v id="$gid" '$2 == id { found = 1 } END { exit !found }'; then
      echo "GID $gid is already used by another group." >&2
      exit 1
    fi
    dseditgroup -o create -n . -i "$gid" -r "$name" "$name"
    echo "Group created: $name"
  fi
done

for def in "${USER_DEFS[@]}"; do
  IFS='|' read -r name uid group real <<< "$def"
  if dscl . -read "/Users/$name" > /dev/null 2>&1; then
    echo "User exists: $name"
  else
    if dscl . -list /Users UniqueID | awk -v id="$uid" '$2 == id { found = 1 } END { exit !found }'; then
      echo "UID $uid is already used by another user." >&2
      exit 1
    fi
    dscl . -create "/Users/$name"
    dscl . -create "/Users/$name" UserShell /bin/zsh
    dscl . -create "/Users/$name" RealName "$real"
    dscl . -create "/Users/$name" UniqueID "$uid"
    dscl . -create "/Users/$name" PrimaryGroupID 20
    dscl . -create "/Users/$name" NFSHomeDirectory "$HOME_ROOT/$name"
    dscl . -create "/Users/$name" IsHidden 1
    mkdir -p "$HOME_ROOT/$name"
    chown "$name:staff" "$HOME_ROOT/$name"
    chmod 700 "$HOME_ROOT/$name"
    echo "User created: $name"
  fi
  dscl . -passwd "/Users/$name" "$PASS"
  dseditgroup -o edit -a "$name" -t user "$group"
  echo "Added $name to $group"
done

echo
echo "Group membership:"
for def in "${GROUP_DEFS[@]}"; do
  IFS='|' read -r name gid <<< "$def"
  echo "$name: $(dscl . -read "/Groups/$name" GroupMembership 2> /dev/null | sed 's/^GroupMembership: *//')"
done
