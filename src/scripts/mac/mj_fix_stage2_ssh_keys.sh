#!/bin/bash
# MJ Fix - Stage 2 (macOS): SSH key-only hardening. Reversible and lockout-safe.
# Works alongside harden_ssh.sh (100-hospital.conf): this adds 000-mj-keys.conf, never edits it.
# Usage: sudo bash mj_fix_stage2_ssh_keys.sh keygen [user] | apply [user] | test [user]
#                                           | break-perms [user] | fix-perms [user] | revert | status [user]
set -u

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo from your normal account." >&2
  exit 1
fi

ACTION="${1:-status}"
# 000- prefix: sshd keeps the FIRST value it reads, so this sorts before 100-hospital.conf
CONF="/etc/ssh/sshd_config.d/000-mj-keys.conf"
HOSPITAL_CONF="/etc/ssh/sshd_config.d/100-hospital.conf"

# macOS starts sshd per connection (launchd), so a new config applies to the next login: no reload needed.
if [ "$ACTION" = "revert" ]; then
  rm -f "$CONF"
  echo "Reverted: password login allowed again (takes effect on the next connection)."
  exit 0
fi

TARGET="${2:-${SUDO_USER:-}}"
if [ -z "$TARGET" ]; then
  echo "No user. Run via sudo from your account, or pass a user name." >&2
  exit 1
fi
HOME_DIR="$(dscl . -read "/Users/$TARGET" NFSHomeDirectory 2> /dev/null | awk '{ print $2 }')"
if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
  echo "User $TARGET or its home folder not found." >&2
  exit 1
fi
GROUP="$(id -gn "$TARGET")"
KEY="$HOME_DIR/.ssh/mj_hospital_ed25519"
AUTH="$HOME_DIR/.ssh/authorized_keys"
SSHD=/usr/sbin/sshd

SSHOPT=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o "UserKnownHostsFile=$HOME_DIR/.ssh/known_hosts")

case "$ACTION" in
  keygen)
    mkdir -p "$HOME_DIR/.ssh"
    chown "$TARGET:$GROUP" "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
    if [ ! -f "$KEY" ]; then
      if [ "${MJ_PASSPHRASE:-0}" = 1 ]; then
        sudo -u "$TARGET" ssh-keygen -t ed25519 -a 100 -f "$KEY" -C "mj-fix-$TARGET"
      else
        sudo -u "$TARGET" ssh-keygen -q -t ed25519 -a 100 -N "" -f "$KEY" -C "mj-fix-$TARGET"
      fi
    fi
    touch "$AUTH"
    if ! grep -qF "$(cut -d' ' -f2 "$KEY.pub")" "$AUTH"; then
      cat "$KEY.pub" >> "$AUTH"
    fi
    chown "$TARGET:$GROUP" "$AUTH"
    chmod 600 "$AUTH"
    echo "Key ready for $TARGET. Fingerprint:"
    ssh-keygen -lf "$KEY.pub"
    ls -ld "$HOME_DIR/.ssh"
    ls -l "$AUTH"
    ;;
  apply)
    if [ ! -s "$AUTH" ]; then
      echo "SAFETY STOP: no authorized key for $TARGET. Run 'keygen' first." >&2
      exit 1
    fi
    if ! grep -q '^Include /etc/ssh/sshd_config.d/' /etc/ssh/sshd_config; then
      echo "This macOS sshd_config does not include /etc/ssh/sshd_config.d. Stopping." >&2
      exit 1
    fi
    if [ -f "$HOSPITAL_CONF" ] && ! grep -E '^AllowUsers ' "$HOSPITAL_CONF" | grep -qw "$TARGET"; then
      echo "WARNING: $TARGET is not in AllowUsers of $HOSPITAL_CONF, so SSH login will fail for it." >&2
    fi
    echo "Keep this session open and confirm key login in a second terminal."
    mkdir -p /etc/ssh/sshd_config.d
    cat > "$CONF" << CFG
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitRootLogin no
PermitEmptyPasswords no
CFG
    chown root:wheel "$CONF"
    chmod 644 "$CONF"
    if "$SSHD" -t; then
      echo "Key-only SSH applied (effective on the next connection)."
    else
      rm -f "$CONF"
      echo "Invalid config, rolled back." >&2
      exit 1
    fi
    ;;
  test)
    echo "--- Remote Login ---"
    systemsetup -getremotelogin 2> /dev/null || echo "(cannot read; check System Settings > General > Sharing > Remote Login)"
    echo "--- effective sshd settings ---"
    "$SSHD" -T -C "user=$TARGET,host=localhost,addr=127.0.0.1" 2> /dev/null | grep -i -E '^(passwordauthentication|pubkeyauthentication|authenticationmethods|permitrootlogin|kbdinteractiveauthentication) '
    echo "--- password login attempt ---"
    sudo -u "$TARGET" ssh "${SSHOPT[@]}" -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive "$TARGET@localhost" true 2>&1 | tail -1
    echo "--- key login attempt ---"
    sudo -u "$TARGET" ssh "${SSHOPT[@]}" -i "$KEY" -o IdentitiesOnly=yes "$TARGET@localhost" 'echo "KEY LOGIN OK as $(whoami)"' 2>&1 | tail -1
    ;;
  break-perms)
    chmod 777 "$HOME_DIR/.ssh"
    echo ".ssh set to 777. Run 'test': the key is now refused (StrictModes)."
    sleep 1
    log show --last 2m --style compact --predicate 'process == "sshd"' 2> /dev/null | grep -i -E 'bad ownership|authentication refused' | tail -1
    ;;
  fix-perms)
    chmod 700 "$HOME_DIR/.ssh"
    chmod 600 "$AUTH"
    echo "Permissions fixed (700/600)."
    ;;
  status)
    if [ -f "$CONF" ]; then cat "$CONF"; else echo "Key-only config not applied."; fi
    ls -ld "$HOME_DIR/.ssh" 2> /dev/null
    ls -l "$AUTH" 2> /dev/null
    ;;
  *)
    echo "Usage: sudo bash $0 keygen|apply|test|break-perms|fix-perms|revert|status [user]"
    exit 1
    ;;
esac
