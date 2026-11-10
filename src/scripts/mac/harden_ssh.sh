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

ACTION="${1:-status}"
DROPIN="/etc/ssh/sshd_config.d/100-hospital.conf"
ALLOWED="$SUDO_USER dr_asha dr_ravi nurse_meera nurse_john admin_priya admin_kiran"

case "$ACTION" in
  apply)
    if ! grep -q '^Include /etc/ssh/sshd_config.d/' /etc/ssh/sshd_config; then
      echo "This macOS sshd_config does not include /etc/ssh/sshd_config.d. Stopping." >&2
      exit 1
    fi
    ssh-keygen -A > /dev/null 2>&1 || true
    mkdir -p /etc/ssh/sshd_config.d
    cat > "$DROPIN" << CONF
PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers $ALLOWED
CONF
    chown root:wheel "$DROPIN"
    chmod 644 "$DROPIN"
    if /usr/sbin/sshd -t; then
      echo "SSH hardening applied."
      echo "Allowed users: $ALLOWED"
    else
      rm -f "$DROPIN"
      echo "The SSH configuration was invalid and has been removed." >&2
      exit 1
    fi
    ;;
  remove)
    rm -f "$DROPIN"
    echo "SSH hardening removed."
    ;;
  status)
    /usr/sbin/sshd -T 2> /dev/null | grep -E '^(permitrootlogin|permitemptypasswords|maxauthtries|logingracetime|x11forwarding|clientaliveinterval|clientalivecountmax|allowusers) ' || true
    ;;
  *)
    echo "Usage: sudo bash harden_ssh.sh apply|remove|status" >&2
    exit 1
    ;;
esac
