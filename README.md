# Hospital IT Server Console

Hackathon project 2: a hospital IT department needs one server for doctors, nurses and administration staff, each with their own accounts and only the folder access their job needs.

This repository holds two things:

1. The server build, as scripts and commands for every stage (macOS, Linux and Windows).
2. A web console (Vite, React, TypeScript, Tailwind) that documents the build: landing page, sign in, dashboard, analysis, runbook and FAQs.

**Tested on:** macOS (Apple Silicon). The Linux and Windows sections give the equivalent commands for those systems.

## What the server delivers

| Requirement | macOS (built and tested) | Linux (Ubuntu) | Windows (PowerShell) |
|---|---|---|---|
| Hostname and network | `scutil`, `networksetup` | `hostnamectl`, `ip` | `Rename-Computer`, `Get-NetIPConfiguration` |
| Users and groups | `dscl`, `dseditgroup` | `useradd`, `groupadd` | `New-LocalUser`, `New-LocalGroup` |
| Expandable storage | sparse disk image | LVM | VHDX volume |
| Folder permissions | `chmod +a` ACLs | `setfacl` | `icacls` |
| Scheduling | `launchd` | `cron` | Task Scheduler |
| Backup and verify | `tar` and `shasum` | `tar` and `sha256sum` | `Compress-Archive` and `Get-FileHash` |
| Firewall | `pf` | `ufw` | Windows Defender Firewall |
| Remote access | `sshd` drop-in file | `sshd` drop-in file | OpenSSH Server |

## Folder access

| Folder | doctors | nurses | hosp_admin |
|---|---|---|---|
| patient-records | read and write | read | none |
| nursing-notes | read | read and write | none |
| billing | none | none | read and write |
| announcements | read | read | read and write |

The administration group is called `hosp_admin` because macOS already has a group named `admin` that grants full administrator rights. On Linux the commands below use `admin`, and on Windows `hosp_admin`.

Sample users: `dr_asha`, `dr_ravi` (doctors), `nurse_meera`, `nurse_john` (nurses), `admin_priya`, `admin_kiran` (administration).

## Run the web console

```
npm install
```

```
npm run dev
```

Open http://localhost:5173. Console accounts are stored in your own browser only.

## Project layout

```
src/pages/              landing, sign in, dashboard, analysis, runbook, FAQs
src/components/ui/      hero landing component
src/scripts/mac/        every macOS server script, including collect_evidence.sh
public/evidence.json    real terminal output, written by collect_evidence.sh
linux/                  Linux user script
README.md               this file
```

## Server setup, stage by stage

Run each block one at a time and check the result before moving on.

### Stage 1: base setup

**macOS**

```
mkdir -p ~/hospital-setup
```

```
scutil --get LocalHostName > ~/hospital-setup/original_localhostname.txt
```

```
sudo scutil --set HostName hospital-srv01
```

```
sudo scutil --set LocalHostName hospital-srv01
```

```
networksetup -getinfo Wi-Fi
```

```
softwareupdate -l
```

```
brew install rsync
```

**Linux (Ubuntu)**

```
sudo hostnamectl set-hostname hospital-srv01
```

```
ip -br addr
```

```
sudo apt update
```

```
sudo apt upgrade -y
```

```
sudo apt install -y acl lvm2 openssh-server ufw rsync
```

**Windows (PowerShell as Administrator)**

```
Rename-Computer -NewName hospital-srv01 -Force
```

```
Get-NetIPConfiguration
```

```
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

Restart Windows to apply the new name. Install Windows updates from Settings, Windows Update.

### Stage 2: users and groups

**macOS**

```
sudo bash src/scripts/mac/create_users.sh
```

The script asks for one shared password for the six sample users and creates them as standard, hidden accounts with private home folders. Check the result:

```
dscl . -read /Groups/doctors GroupMembership
```

```
id nurse_meera
```

```
dseditgroup -o checkmember -m nurse_meera admin
```

**Linux (Ubuntu)**

```
sudo bash linux/create_users.sh
```

```
getent group doctors nurses admin
```

**Windows (PowerShell as Administrator)**

```
$pw = Read-Host -AsSecureString "Password for the sample users"
```

```
"doctors","nurses","hosp_admin" | ForEach-Object { New-LocalGroup -Name $_ }
```

```
$users = @{ dr_asha="doctors"; dr_ravi="doctors"; nurse_meera="nurses"; nurse_john="nurses"; admin_priya="hosp_admin"; admin_kiran="hosp_admin" }
```

```
$users.GetEnumerator() | ForEach-Object { New-LocalUser -Name $_.Key -Password $pw -AccountNeverExpires | Out-Null; Add-LocalGroupMember -Group $_.Value -Member $_.Key }
```

### Stage 3: storage and ACL folders

**macOS**

```
sudo bash src/scripts/mac/setup_storage.sh
```

This creates a 2 GB sparse disk image, mounts it at `/Volumes/hospital` with ownership enabled, creates the four folders and applies the ACLs. Check it:

```
ls -led /Volumes/hospital/*
```

```
sudo -u nurse_meera touch /Volumes/hospital/patient-records/test.txt
```

The nurse gets Permission denied. The disk image is unmounted after a restart, so run the same script again to remount it.

**Linux (Ubuntu)**

```
sudo truncate -s 2G /srv/hospital.img
```

```
LOOP=$(sudo losetup --find --show /srv/hospital.img)
```

```
sudo pvcreate "$LOOP"
```

```
sudo vgcreate hospital_vg "$LOOP"
```

```
sudo lvcreate -n data -l 100%FREE hospital_vg
```

```
sudo mkfs.ext4 /dev/hospital_vg/data
```

```
sudo mkdir -p /hospital
```

```
sudo mount /dev/hospital_vg/data /hospital
```

```
sudo mkdir -p /hospital/patient-records /hospital/nursing-notes /hospital/billing /hospital/announcements
```

```
sudo chmod 700 /hospital/patient-records /hospital/nursing-notes /hospital/billing /hospital/announcements
```

Apply the ACLs (the `-d` entries are defaults for new files):

```
sudo setfacl -m g:doctors:rwx,g:nurses:r-x /hospital/patient-records
```

```
sudo setfacl -d -m g:doctors:rwx,g:nurses:r-x /hospital/patient-records
```

```
sudo setfacl -m g:doctors:r-x,g:nurses:rwx /hospital/nursing-notes
```

```
sudo setfacl -d -m g:doctors:r-x,g:nurses:rwx /hospital/nursing-notes
```

```
sudo setfacl -m g:admin:rwx /hospital/billing
```

```
sudo setfacl -d -m g:admin:rwx /hospital/billing
```

```
sudo setfacl -m g:doctors:r-x,g:nurses:r-x,g:admin:rwx /hospital/announcements
```

```
sudo setfacl -d -m g:doctors:r-x,g:nurses:r-x,g:admin:rwx /hospital/announcements
```

```
getfacl /hospital/patient-records
```

To extend the volume later, grow the image file and run `sudo lvextend -r -L +1G /dev/hospital_vg/data`. A loop-backed volume must be attached again after a reboot (`losetup`, `vgchange -ay`, `mount`).

**Windows (PowerShell as Administrator)**

```
New-Item -ItemType Directory -Path C:\hospital-storage -Force
```

```
@"
create vdisk file=C:\hospital-storage\hospital.vhdx maximum=2048 type=expandable
select vdisk file=C:\hospital-storage\hospital.vhdx
attach vdisk
create partition primary
format fs=ntfs label=hospital quick
assign letter=H
"@ | Set-Content C:\hospital-storage\make.txt
```

```
diskpart /s C:\hospital-storage\make.txt
```

```
New-Item -ItemType Directory -Path H:\patient-records,H:\nursing-notes,H:\billing,H:\announcements
```

```
icacls H:\patient-records /inheritance:r /grant "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "doctors:(OI)(CI)M" "nurses:(OI)(CI)RX"
```

```
icacls H:\nursing-notes /inheritance:r /grant "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "doctors:(OI)(CI)RX" "nurses:(OI)(CI)M"
```

```
icacls H:\billing /inheritance:r /grant "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "hosp_admin:(OI)(CI)M"
```

```
icacls H:\announcements /inheritance:r /grant "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "doctors:(OI)(CI)RX" "nurses:(OI)(CI)RX" "hosp_admin:(OI)(CI)M"
```

### Stage 4: automation and backup

**macOS**

```
sudo bash src/scripts/mac/install_automation.sh
```

This installs the scripts to `/usr/local/hospital/bin` and schedules two `launchd` jobs: the backup every day at 02:00 and the disk check every hour. Backups go to `/Users/Shared/hospital-backups`, outside the disk image, and the last seven are kept.

```
sudo launchctl kickstart -k system/com.hospital.backup
```

```
sudo cat /var/log/hospital-backup.log
```

```
sudo /usr/local/hospital/bin/hospital_verify.sh
```

```
sudo /usr/local/hospital/bin/hospital_disk_check.sh 1
```

**Linux (Ubuntu)**

```
sudo tee /usr/local/bin/hospital_backup.sh > /dev/null << 'EOF'
#!/bin/bash
set -eu
DEST=/var/backups/hospital
mkdir -p "$DEST"
NAME="hospital-data-$(date +%Y%m%d-%H%M%S).tar.gz"
tar --acls -czf "$DEST/$NAME" -C /hospital patient-records nursing-notes billing announcements
(cd "$DEST" && sha256sum "$NAME" > "$NAME.sha256" && sha256sum -c "$NAME.sha256")
ls -1t "$DEST"/hospital-data-*.tar.gz | tail -n +8 | while read -r old; do rm -f "$old" "$old.sha256"; done
EOF
```

```
sudo tee /usr/local/bin/hospital_disk_check.sh > /dev/null << 'EOF'
#!/bin/bash
USED=$(df --output=pcent /hospital | tail -n 1 | tr -dc '0-9')
if [ "$USED" -ge "${1:-80}" ]; then
  echo "$(date '+%F %T') WARNING: /hospital is ${USED}% full" | tee -a /var/log/hospital-disk.log
fi
EOF
```

```
sudo chmod +x /usr/local/bin/hospital_backup.sh /usr/local/bin/hospital_disk_check.sh
```

```
sudo tee /etc/cron.d/hospital > /dev/null << 'EOF'
0 2 * * * root /usr/local/bin/hospital_backup.sh
0 * * * * root /usr/local/bin/hospital_disk_check.sh
EOF
```

```
sudo /usr/local/bin/hospital_backup.sh
```

**Windows (PowerShell as Administrator)**

```
@'
$dest = "C:\hospital-backups"
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$name = "hospital-data-$(Get-Date -Format yyyyMMdd-HHmmss).zip"
Compress-Archive -Path H:\patient-records,H:\nursing-notes,H:\billing,H:\announcements -DestinationPath "$dest\$name"
(Get-FileHash "$dest\$name" -Algorithm SHA256).Hash | Set-Content "$dest\$name.sha256"
'@ | Set-Content C:\hospital-storage\backup.ps1
```

```
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -File C:\hospital-storage\backup.ps1"
```

```
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
```

```
Register-ScheduledTask -TaskName "HospitalBackup" -Action $action -Trigger $trigger -User "SYSTEM" -RunLevel Highest
```

```
Start-ScheduledTask -TaskName "HospitalBackup"
```

### Stage 5: security

**macOS**

```
sudo bash src/scripts/mac/firewall.sh check
```

```
sudo bash src/scripts/mac/firewall.sh on
```

```
sudo systemsetup -setremotelogin on
```

```
sudo bash src/scripts/mac/harden_ssh.sh apply
```

```
sudo bash src/scripts/mac/permission_audit.sh
```

The firewall allows SSH only from your local network and rolls itself back if the network check fails. `harden_ssh.sh` turns off root login, limits password tries, restricts logins to the named users and adds them to the macOS SSH access group. The audit checks every folder, ACL and setting and prints PASS or FAIL.

**Linux (Ubuntu)**

```
sudo ufw default deny incoming
```

```
sudo ufw default allow outgoing
```

```
sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp
```

```
sudo ufw enable
```

Replace `ubuntu` below with your own login name and the subnet above with your network:

```
sudo tee /etc/ssh/sshd_config.d/100-hospital.conf > /dev/null << 'EOF'
PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 60
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers ubuntu dr_asha dr_ravi nurse_meera nurse_john admin_priya admin_kiran
EOF
```

```
sudo sshd -t
```

```
sudo systemctl reload ssh
```

**Windows (PowerShell as Administrator)**

```
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -DefaultInboundAction Block
```

```
New-NetFirewallRule -DisplayName "Hospital SSH" -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress LocalSubnet -Action Allow
```

```
Start-Service sshd
```

```
Set-Service -Name sshd -StartupType Automatic
```

Windows has no root account, so the settings below block the built-in Administrator and allow named users. They must go at the top of the file, before the `Match` block:

```
$cfg = "C:\ProgramData\ssh\sshd_config"
$new = "MaxAuthTries 3`r`nLoginGraceTime 60`r`nDenyUsers Administrator`r`nAllowUsers dr_asha dr_ravi nurse_meera nurse_john admin_priya admin_kiran`r`n"
Set-Content $cfg ($new + (Get-Content $cfg -Raw))
```

```
Restart-Service sshd
```

### Stage 6: testing, recovery and demo

**macOS**

```
sudo bash src/scripts/mac/role_tests.sh
```

```
sudo launchctl kickstart -k system/com.hospital.backup
```

```
sudo rm -rf /Volumes/hospital/patient-records
```

```
sudo bash src/scripts/mac/hospital_restore.sh
```

```
sudo bash src/scripts/mac/role_tests.sh
```

**Linux (Ubuntu)**

```
sudo -u nurse_meera touch /hospital/patient-records/test.txt
```

```
sudo /usr/local/bin/hospital_backup.sh
```

```
sudo rm -rf /hospital/patient-records
```

```
sudo tar --acls -xzf "$(ls -1t /var/backups/hospital/hospital-data-*.tar.gz | head -n 1)" -C /hospital
```

```
getfacl /hospital/patient-records
```

**Windows (PowerShell as Administrator)**

```
Remove-Item H:\patient-records -Recurse -Force
```

```
$zip = Get-ChildItem C:\hospital-backups\hospital-data-*.zip | Sort-Object LastWriteTime | Select-Object -Last 1
```

```
Expand-Archive -Path $zip.FullName -DestinationPath H:\ -Force
```

```
icacls H:\patient-records /inheritance:r /grant "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "doctors:(OI)(CI)M" "nurses:(OI)(CI)RX"
```

To test a role on Windows, run `runas /user:nurse_meera cmd` and try to write into `H:\patient-records`.

## Evidence page

The console shows real terminal output. `collect_evidence.sh` runs 29 read-only checks on the Mac, one or more per stage. Each check records the command, its real output, the exit code and a PASS or FAIL result in `public/evidence.json`. The Evidence page reads that file and refreshes by itself every few seconds, and the Dashboard marks a stage as verified only when every check for it passed.

```
sudo bash src/scripts/mac/collect_evidence.sh
```

Run it again at any time to refresh. A web page cannot run commands itself, so this script is how terminal output reaches the site. The file holds your local IP address and username, so check it before you share it.

## Demo script (about 8 minutes)

1. Run `collect_evidence.sh`, then open the Evidence page: every stage shows its real output and a PASS badge. Show the access matrix on the Analysis page.
2. Run the role tests. Every cell reads ok.
3. As a nurse, try to write into patient-records: Permission denied. As a doctor, write a record: it works.
4. Run a backup, then verify it: OK and the file count.
5. Delete patient-records on purpose, then restore it. The record is back with its permissions.
6. Detach the disk. The disk check warns, and the setup script brings the volume back.
7. Show the firewall rules, try root over SSH (denied) and run the permission audit: All checks passed.

## Undo everything (macOS)

```
sudo bash src/scripts/mac/uninstall_automation.sh
```

```
sudo bash src/scripts/mac/firewall.sh off
```

```
sudo bash src/scripts/mac/harden_ssh.sh remove
```

```
sudo systemsetup -setremotelogin off
```

```
sudo bash src/scripts/mac/teardown_storage.sh
```

```
sudo bash src/scripts/mac/remove_users.sh
```

```
sudo rm -rf /Users/Shared/hospital-backups
```

The hostname change is saved in `~/hospital-setup/original_localhostname.txt`. To restore it:

```
sudo scutil --set HostName "$(cat ~/hospital-setup/original_localhostname.txt)"
```

```
sudo scutil --set LocalHostName "$(cat ~/hospital-setup/original_localhostname.txt)"
```

## Security note

This is a demo build. The sample users share one password, and SSH is reachable from the local network while Remote Login is on. Use a strong password if the machine is on a shared network, and run the undo steps when you are finished.
