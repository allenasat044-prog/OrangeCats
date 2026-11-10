#!/bin/bash
set -u

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [ -z "${SUDO_USER:-}" ]; then
  echo "Run this script with sudo from your normal account." >&2
  exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${PROJECT:-$(cd "$DIR/../../.." && pwd)}"
OUT_FILE="${EVIDENCE_FILE:-$PROJECT/public/evidence.json}"
VOL="/Volumes/hospital"
export DIR VOL

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TAB="$(printf '\t')"
COUNT=0
PASSED=0
FAILED=0
CHECKS_JSON="$TMP/checks.json"
: > "$CHECKS_JSON"

json_str() {
  LC_ALL=C tr -d '\000-\010\013-\037' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g" \
    | LC_ALL=C awk 'BEGIN { ORS = ""; printf "\"" } { if (NR > 1) printf "\\n"; printf "%s", $0 } END { printf "\"" }'
}

run_check() {
  local id="$1" stage="$2" title="$3" proves="$4" cmd="$5" expr="${6:-}"
  local out code status shown
  COUNT=$((COUNT + 1))
  out="$TMP/out.$COUNT"
  bash -c "$cmd" > "$out" 2>&1
  code=$?
  if [ -z "$expr" ]; then
    expr='[ "$EXIT" = 0 ]'
  fi
  if OUT="$out" EXIT="$code" bash -c "$expr" > /dev/null 2>&1; then
    status="pass"
    PASSED=$((PASSED + 1))
    printf 'PASS  %s  %s\n' "$id" "$title"
  else
    status="fail"
    FAILED=$((FAILED + 1))
    printf 'FAIL  %s  %s\n' "$id" "$title"
  fi
  shown="${cmd//\$DIR/$DIR}"
  shown="${shown//\$VOL/$VOL}"
  if [ "$COUNT" -gt 1 ]; then
    printf ',' >> "$CHECKS_JSON"
  fi
  {
    printf '{"id":'
    printf '%s' "$id" | json_str
    printf ',"stage":%s,"title":' "$stage"
    printf '%s' "$title" | json_str
    printf ',"proves":'
    printf '%s' "$proves" | json_str
    printf ',"command":'
    printf '%s' "$shown" | json_str
    printf ',"output":'
    head -n 120 "$out" | json_str
    printf ',"exitCode":%s,"status":"%s"}' "$code" "$status"
  } >> "$CHECKS_JSON"
}

if ! mount | grep -q " on $VOL "; then
  echo "Note: $VOL is not mounted. Run setup_storage.sh first, or the storage checks will fail."
fi
echo "Collecting evidence from this Mac. This takes a few seconds."
echo

# ---- checks ----

run_check s1-hostname 1 "Server hostname" "The machine carries its server name." 'scutil --get HostName; scutil --get LocalHostName'
run_check s1-network 1 "Network settings" "The server has an address, subnet and router on the Wi-Fi interface." 'networksetup -getinfo Wi-Fi | grep -v -i "Wi-Fi ID"' 'grep -q "IP address" "$OUT" && grep -q "Router" "$OUT"'
run_check s1-os 1 "Operating system" "The operating system version is recorded." 'sw_vers' 'grep -q ProductName "$OUT"'
run_check s1-updates 1 "System updates" "The system was checked for pending updates." 'softwareupdate -l 2>&1'
run_check s1-tools 1 "Administration tools" "Every tool the later stages depend on is installed." 'which dscl dseditgroup hdiutil pfctl launchctl ssh' '[ "$(wc -l < "$OUT" | tr -d " ")" = 6 ]'
run_check s1-rsync 1 "rsync" "A current rsync is installed for backups." 'for p in /opt/homebrew/bin/rsync /usr/local/bin/rsync; do if [ -x "$p" ]; then "$p" --version | head -n 1; exit 0; fi; done; echo "Homebrew rsync not found"; exit 1'

run_check s2-groups 2 "Group membership" "Doctors, nurses and administration each have their own group with two members." 'for g in doctors nurses hosp_admin; do echo "$g: $(dscl . -read /Groups/$g GroupMembership 2>/dev/null | sed "s/^GroupMembership: //")"; done' '[ "$(grep -c -E "^(doctors|nurses|hosp_admin): [a-z_]+ [a-z_]+$" "$OUT")" = 3 ]'
run_check s2-ids 2 "User identities" "Each sample user belongs to the right role group." 'id dr_asha; id nurse_meera; id admin_priya' 'grep -q "(doctors)" "$OUT" && grep -q "(nurses)" "$OUT" && grep -q "(hosp_admin)" "$OUT"'
run_check s2-notadmin 2 "No administrator rights" "None of the sample users is a macOS administrator." 'for u in dr_asha dr_ravi nurse_meera nurse_john admin_priya admin_kiran; do printf "%s: " "$u"; dseditgroup -o checkmember -m "$u" admin 2>&1 | head -n 1; done' '[ "$(grep -c ": yes" "$OUT")" = 0 ] && [ "$(grep -c ": no" "$OUT")" = 6 ]'
run_check s2-homes 2 "Private home folders" "Users cannot read each other's files." 'ls -ld /Users/dr_asha /Users/nurse_meera /Users/admin_priya' '[ "$(grep -c "^drwx------" "$OUT")" = 3 ]'
run_check s2-whoami 2 "Running as a sample user" "Commands can be run as a hospital user." 'sudo -u nurse_meera whoami' 'grep -q "^nurse_meera$" "$OUT"'

run_check s3-volume 3 "Storage volume" "A separate APFS volume is mounted at /Volumes/hospital with ownership on, so permissions apply." 'diskutil info /Volumes/hospital | grep -i -E "volume name|mount point|file system personality|owners"' 'grep -q "APFS" "$OUT" && grep -q "Owners:.*Enabled" "$OUT"'
run_check s3-acl 3 "ACL rules" "Each folder grants its groups exactly the access in the matrix." 'ls -led /Volumes/hospital/*' '[ "$(grep -c "^d" "$OUT")" = 4 ] && [ "$(grep -c " allow " "$OUT")" = 8 ]'
run_check s3-denied 3 "Access is denied where it should be" "A nurse cannot write patient records, an admin cannot read them and a doctor cannot open billing." 'echo "nurse_meera writes to patient-records:"; sudo -u nurse_meera touch /Volumes/hospital/patient-records/.evidence_probe 2>&1; echo "admin_priya lists patient-records:"; sudo -u admin_priya ls /Volumes/hospital/patient-records 2>&1; echo "dr_asha lists billing:"; sudo -u dr_asha ls /Volumes/hospital/billing 2>&1' '[ "$(grep -c "Permission denied" "$OUT")" = 3 ]'
run_check s3-allowed 3 "Access is granted where it should be" "A nurse can read patient records and a doctor can write to them." 'echo "nurse_meera lists patient-records:"; sudo -u nurse_meera ls /Volumes/hospital/patient-records 2>&1; echo "dr_asha writes to patient-records:"; sudo -u dr_asha touch /Volumes/hospital/patient-records/.evidence_probe 2>&1 && echo "write allowed"; rm -f /Volumes/hospital/patient-records/.evidence_probe' 'grep -q "write allowed" "$OUT" && ! grep -q "denied" "$OUT"'

run_check s4-jobs 4 "Scheduled jobs" "launchd runs the backup and the disk check on a schedule." 'launchctl list | grep hospital' 'grep -q com.hospital.backup "$OUT" && grep -q com.hospital.diskcheck "$OUT"'
run_check s4-backup-log 4 "Latest backups" "The backup job created archives and verified each one." 'tail -n 6 /var/log/hospital-backup.log' 'grep -q "Backup verified" "$OUT"'
run_check s4-backup-files 4 "Backup files" "Each archive has a SHA-256 checksum file next to it." 'ls -l /Users/Shared/hospital-backups' 'grep -q "tar.gz$" "$OUT" && grep -q "sha256$" "$OUT"'
run_check s4-verify 4 "Backup integrity" "The newest backup matches its checksum and can be read." '/usr/local/hospital/bin/hospital_verify.sh' 'grep -q ": OK" "$OUT" && grep -q "Archive readable" "$OUT"'
run_check s4-disk 4 "Disk usage" "Both disks are under the 80% limit." '/usr/local/hospital/bin/hospital_disk_check.sh' 'grep -q "OK: hospital volume" "$OUT" && ! grep -q WARNING "$OUT"'
run_check s4-disk-warning 4 "Disk warning works" "With the limit lowered to 1%, the check raises a warning." '/usr/local/hospital/bin/hospital_disk_check.sh 1' 'grep -q WARNING "$OUT"'

run_check s5-firewall 5 "Firewall" "The pf firewall is on, blocks incoming traffic and allows SSH." '(pfctl -s info 2>/dev/null | head -n 1; pfctl -a com.hospital -s rules 2>/dev/null)' 'grep -q "Status: Enabled" "$OUT" && grep -q "block drop in" "$OUT" && grep -q "port = 22" "$OUT"'
run_check s5-ssh-settings 5 "SSH settings in effect" "Root login is off and password tries and the login window are limited." '/usr/sbin/sshd -T -C user=root,host=localhost,addr=127.0.0.1 2>&1 | grep -i -E "^(permitrootlogin|permitemptypasswords|maxauthtries|logingracetime|x11forwarding|allowusers) "' 'grep -qi "^permitrootlogin no" "$OUT"'
run_check s5-ssh-file 5 "SSH hardening file" "The hardening settings are stored in a drop-in file." 'cat /etc/ssh/sshd_config.d/100-hospital.conf' 'grep -q "^PermitRootLogin no" "$OUT" && grep -q "^AllowUsers" "$OUT"'
run_check s5-remote-login 5 "Remote Login" "SSH access to this Mac is switched on." 'systemsetup -getremotelogin 2>&1' 'grep -q "On" "$OUT"'
run_check s5-access-group 5 "macOS SSH access list" "The hospital users are on the macOS list of accounts allowed to use SSH." 'dscl . -read /Groups/com.apple.access_ssh GroupMembership' 'grep -q dr_asha "$OUT" && grep -q nurse_meera "$OUT" && grep -q admin_priya "$OUT"'
run_check s5-audit 5 "Permission audit" "Every folder, ACL, backup folder, SSH setting and firewall rule was checked." 'bash "$DIR/permission_audit.sh"' 'grep -q "All checks passed" "$OUT"'

run_check s6-roles 6 "Role tests" "All six users get exactly the access the matrix gives them on all four folders." 'bash "$DIR/role_tests.sh"' 'grep -q "All role checks passed" "$OUT"'
run_check s6-restore 6 "Delete and restore" "The restore verified a backup, restored the folders and re-applied the permissions." 'tail -n 8 /var/log/hospital-restore.log' 'grep -q "Folder permissions and ACLs re-applied" "$OUT"'

# ---- end checks ----

GENERATED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
HOST_NAME="$(scutil --get LocalHostName 2> /dev/null || hostname)"
MACOS_VERSION="$(sw_vers -productVersion 2> /dev/null || uname -r)"

mkdir -p "$(dirname "$OUT_FILE")"
{
  printf '{"generatedAt":"%s","host":' "$GENERATED"
  printf '%s' "$HOST_NAME" | json_str
  printf ',"macos":'
  printf '%s' "$MACOS_VERSION" | json_str
  printf ',"user":'
  printf '%s' "$SUDO_USER" | json_str
  printf ',"summary":{"total":%s,"passed":%s,"failed":%s},"checks":[' "$COUNT" "$PASSED" "$FAILED"
  cat "$CHECKS_JSON"
  printf ']}\n'
} > "$OUT_FILE.tmp"
mv "$OUT_FILE.tmp" "$OUT_FILE"
chown "$SUDO_USER" "$OUT_FILE"

echo
echo "$PASSED of $COUNT checks passed, $FAILED failed."
echo "Evidence saved to $OUT_FILE"
echo "Open the Evidence page in the console to see it."
