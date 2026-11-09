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

SRC="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-/usr/local/hospital}"
LAUNCHD_DIR="${LAUNCHD_DIR:-/Library/LaunchDaemons}"
OWNER_HOME="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory | awk '{ print $2 }')"
BACKUP_DIR="/Users/Shared/hospital-backups"

mkdir -p "$PREFIX/bin" "$PREFIX/etc" "$BACKUP_DIR"
chown root:wheel "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

for s in hospital_backup.sh hospital_verify.sh hospital_disk_check.sh; do
  install -m 755 "$SRC/$s" "$PREFIX/bin/$s"
  chown root:wheel "$PREFIX/bin/$s"
done

cat > "$PREFIX/etc/hospital.conf" << CONF
VOLUME=/Volumes/hospital
IMAGE=$OWNER_HOME/hospital-storage/hospital.sparseimage
BACKUP_DIR=$BACKUP_DIR
FOLDERS="patient-records nursing-notes billing announcements"
THRESHOLD=80
KEEP=7
CONF
chown root:wheel "$PREFIX/etc/hospital.conf"
chmod 644 "$PREFIX/etc/hospital.conf"

cat > "$LAUNCHD_DIR/com.hospital.backup.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.hospital.backup</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PREFIX/bin/hospital_backup.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>2</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>/var/log/hospital-backup.launchd.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/hospital-backup.launchd.log</string>
</dict>
</plist>
PLIST

cat > "$LAUNCHD_DIR/com.hospital.diskcheck.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.hospital.diskcheck</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PREFIX/bin/hospital_disk_check.sh</string>
  </array>
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>StandardOutPath</key>
  <string>/var/log/hospital-disk.launchd.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/hospital-disk.launchd.log</string>
</dict>
</plist>
PLIST

for label in com.hospital.backup com.hospital.diskcheck; do
  chown root:wheel "$LAUNCHD_DIR/$label.plist"
  chmod 644 "$LAUNCHD_DIR/$label.plist"
  launchctl bootout "system/$label" > /dev/null 2>&1 || true
  launchctl bootstrap system "$LAUNCHD_DIR/$label.plist"
  echo "Scheduled: $label"
done

echo
echo "Scripts installed in $PREFIX/bin"
echo "Backups are stored in $BACKUP_DIR"
echo "Backup runs daily at 02:00 and the disk check runs every hour."
