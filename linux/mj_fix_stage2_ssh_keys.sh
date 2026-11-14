#!/usr/bin/env bash
# MJ Fix - Stage 2 (Ubuntu): SSH key-only hardening. Reversible and lockout-safe.
# Usage: sudo bash mj_fix_stage2_ssh_keys.sh keygen [user] | apply [user] | test [user]
#                                           | break-perms [user] | fix-perms [user] | revert | status [user]
set -u
[[ $EUID -eq 0 ]] || { echo "Run with sudo from your normal account." >&2; exit 1; }
ACTION="${1:-status}"
CONF="/etc/ssh/sshd_config.d/00-mj-keys.conf"
reload_ssh() { systemctl reload ssh 2>/dev/null || service ssh reload 2>/dev/null || kill -HUP "$(cat /run/sshd.pid 2>/dev/null)" 2>/dev/null; }
if [[ "$ACTION" == revert ]]; then   # needs no user
  rm -f "$CONF"; sshd -t && reload_ssh && echo "Reverted: password login allowed again."; exit 0
fi
TARGET="${2:-${SUDO_USER:-}}"
[[ -n "$TARGET" ]] || { echo "No user. Run via sudo from your account, or pass a user name." >&2; exit 1; }
HOME_DIR="$(getent passwd "$TARGET" | cut -d: -f6)"
[[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || { echo "User $TARGET or its home folder not found." >&2; exit 1; }
GROUP="$(id -gn "$TARGET")"
KEY="$HOME_DIR/.ssh/mj_hospital_ed25519"
AUTH="$HOME_DIR/.ssh/authorized_keys"
# CONF is named 00-... because sshd keeps the FIRST value it reads (must sort before 50-cloud-init.conf)
as_user() { sudo -u "$TARGET" "$@"; }
SSHOPT=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o UserKnownHostsFile="$HOME_DIR/.ssh/known_hosts")

case "$ACTION" in
  keygen)
    install -d -m 700 -o "$TARGET" -g "$GROUP" "$HOME_DIR/.ssh"
    if [[ ! -f "$KEY" ]]; then
      if [[ "${MJ_PASSPHRASE:-0}" == 1 ]]; then as_user ssh-keygen -t ed25519 -a 100 -f "$KEY" -C "mj-fix-$TARGET"
      else as_user ssh-keygen -q -t ed25519 -a 100 -N "" -f "$KEY" -C "mj-fix-$TARGET"; fi
    fi
    touch "$AUTH"
    grep -qF "$(cut -d' ' -f2 "$KEY.pub")" "$AUTH" || cat "$KEY.pub" >> "$AUTH"
    chown "$TARGET:$GROUP" "$AUTH"; chmod 600 "$AUTH"
    echo "Key ready for $TARGET. Fingerprint:"; ssh-keygen -lf "$KEY.pub"
    ls -ld "$HOME_DIR/.ssh"; ls -l "$AUTH";;
  apply)
    [[ -s "$AUTH" ]] || { echo "SAFETY STOP: no authorized key for $TARGET. Run 'keygen' first." >&2; exit 1; }
    echo "Keep this session open and confirm key login in a second terminal."
    cat > "$CONF" << CFG
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
PermitRootLogin no
PermitEmptyPasswords no
CFG
    chmod 644 "$CONF"
    if sshd -t; then reload_ssh && echo "Key-only SSH applied."
    else rm -f "$CONF"; echo "Invalid config, rolled back." >&2; exit 1; fi;;
  test)
    echo "--- effective sshd settings ---"
    sshd -T 2>/dev/null | grep -E '^(passwordauthentication|pubkeyauthentication|authenticationmethods|permitrootlogin|kbdinteractiveauthentication) '
    echo "--- password login attempt ---"
    as_user ssh "${SSHOPT[@]}" -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive "$TARGET@localhost" true 2>&1 | tail -1
    echo "--- key login attempt ---"
    as_user ssh "${SSHOPT[@]}" -i "$KEY" -o IdentitiesOnly=yes "$TARGET@localhost" 'echo "KEY LOGIN OK as $(whoami)"' 2>&1 | tail -1;;
  break-perms)
    chmod 777 "$HOME_DIR/.ssh"; echo ".ssh set to 777. Run 'test': the key is now refused (StrictModes)."
    sleep 1; (journalctl -u ssh --no-pager -n 20 2>/dev/null; cat /var/log/auth.log 2>/dev/null) | grep -i "bad ownership" | tail -1;;
  fix-perms) chmod 700 "$HOME_DIR/.ssh"; chmod 600 "$AUTH"; echo "Permissions fixed (700/600).";;
  status) if [[ -f "$CONF" ]]; then cat "$CONF"; else echo "Key-only config not applied."; fi
          ls -ld "$HOME_DIR/.ssh" 2>/dev/null; ls -l "$AUTH" 2>/dev/null;;
  *) echo "Usage: sudo bash $0 keygen|apply|test|break-perms|fix-perms|revert|status [user]"; exit 1;;
esac
