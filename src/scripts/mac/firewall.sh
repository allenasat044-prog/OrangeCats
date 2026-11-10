#!/bin/bash
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

ACTION="${1:-status}"
PREFIX="${PREFIX:-/usr/local/hospital}"
ANCHOR_FILE="/etc/pf.anchors/com.hospital"
MAIN_CONF="/etc/pf.hospital.conf"
MARKER="$PREFIX/etc/pf_was_disabled"

pf_enabled() {
  pfctl -s info 2> /dev/null | grep -q '^Status: Enabled'
}

build() {
  IF="$(route -n get default 2> /dev/null | awk '/interface:/ { print $2 }')"
  GATEWAY="$(route -n get default 2> /dev/null | awk '/gateway:/ { print $2 }')"
  if [ -z "$IF" ] || [ -z "$GATEWAY" ]; then
    echo "Could not find the active network interface." >&2
    exit 1
  fi
  mkdir -p /etc/pf.anchors
  cat > "$ANCHOR_FILE" << RULES
pass quick on lo0 all
block in on $IF all
pass out on $IF all keep state
pass in on $IF proto tcp from ($IF:network) to any port 22 keep state
pass in on $IF proto icmp all keep state
pass in on $IF inet6 proto icmp6 all keep state
pass in on $IF proto udp from any port 67 to any port 68 keep state
pass in on $IF proto udp from any to any port 5353 keep state
RULES
  cp /etc/pf.conf "$MAIN_CONF"
  {
    echo 'anchor "com.hospital"'
    echo "load anchor \"com.hospital\" from \"$ANCHOR_FILE\""
  } >> "$MAIN_CONF"
  pfctl -nf "$MAIN_CONF"
}

rollback() {
  echo "$1" >&2
  pfctl -f /etc/pf.conf > /dev/null 2>&1 || true
  if [ -f "$MARKER" ]; then
    pfctl -d > /dev/null 2>&1 || true
    rm -f "$MARKER"
  fi
  echo "Firewall rules were rolled back." >&2
  exit 1
}

case "$ACTION" in
  check)
    build
    echo "Rules are valid for interface $IF:"
    cat "$ANCHOR_FILE"
    ;;
  on)
    build
    mkdir -p "$PREFIX/etc"
    if pf_enabled; then
      rm -f "$MARKER"
    else
      touch "$MARKER"
    fi
    pfctl -f "$MAIN_CONF" 2> /dev/null
    pfctl -e > /dev/null 2>&1 || true
    if ping -c 2 -t 4 "$GATEWAY" > /dev/null 2>&1 || curl -s -o /dev/null --max-time 6 https://www.apple.com; then
      echo "Firewall is on. Network check passed on $IF."
    else
      rollback "Network check failed after enabling the firewall."
    fi
    ;;
  off)
    pfctl -f /etc/pf.conf > /dev/null 2>&1 || true
    if [ -f "$MARKER" ]; then
      pfctl -d > /dev/null 2>&1 || true
      rm -f "$MARKER"
    fi
    rm -f "$ANCHOR_FILE" "$MAIN_CONF"
    echo "Firewall rules removed."
    ;;
  status)
    pfctl -s info 2> /dev/null | head -n 2
    echo
    pfctl -a com.hospital -s rules 2> /dev/null || true
    ;;
  *)
    echo "Usage: sudo bash firewall.sh check|on|off|status" >&2
    exit 1
    ;;
esac
