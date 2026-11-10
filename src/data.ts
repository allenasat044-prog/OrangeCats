import createUsers from "./scripts/mac/create_users.sh?raw";
import removeUsers from "./scripts/mac/remove_users.sh?raw";
import setupStorage from "./scripts/mac/setup_storage.sh?raw";
import teardownStorage from "./scripts/mac/teardown_storage.sh?raw";
import installAutomation from "./scripts/mac/install_automation.sh?raw";
import hospitalBackup from "./scripts/mac/hospital_backup.sh?raw";
import hospitalVerify from "./scripts/mac/hospital_verify.sh?raw";
import hospitalDiskCheck from "./scripts/mac/hospital_disk_check.sh?raw";
import uninstallAutomation from "./scripts/mac/uninstall_automation.sh?raw";
import firewall from "./scripts/mac/firewall.sh?raw";
import hardenSsh from "./scripts/mac/harden_ssh.sh?raw";
import permissionAudit from "./scripts/mac/permission_audit.sh?raw";
import hospitalRestore from "./scripts/mac/hospital_restore.sh?raw";
import roleTests from "./scripts/mac/role_tests.sh?raw";
import collectEvidence from "./scripts/mac/collect_evidence.sh?raw";

export type Role = "doctors" | "nurses" | "hosp_admin";
export type Level = "rw" | "r" | "none";

export const roles: { id: Role; label: string; duty: string }[] = [
  { id: "doctors", label: "Doctors", duty: "Read and edit patient records and read nursing notes." },
  { id: "nurses", label: "Nurses", duty: "Read patient records and read and write nursing notes." },
  { id: "hosp_admin", label: "Administration", duty: "Manage billing and announcements with no access to medical files." },
];

export const folders: { id: string; label: string; access: Record<Role, Level> }[] = [
  { id: "patient-records", label: "Patient Records", access: { doctors: "rw", nurses: "r", hosp_admin: "none" } },
  { id: "nursing-notes", label: "Nursing Notes", access: { doctors: "r", nurses: "rw", hosp_admin: "none" } },
  { id: "billing", label: "Billing", access: { doctors: "none", nurses: "none", hosp_admin: "rw" } },
  { id: "announcements", label: "Announcements", access: { doctors: "r", nurses: "r", hosp_admin: "rw" } },
];

export const aclRights: Record<Level, string> = {
  rw: "list,search,add_file,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,file_inherit,directory_inherit",
  r: "list,search,readattr,readextattr,file_inherit,directory_inherit",
  none: "",
};

export type Script = { name: string; path: string; body: string };

export type Stage = {
  id: number;
  title: string;
  minutes: number;
  tasks: string[];
  scripts?: Script[];
  commands?: string[];
  expected?: string[];
};

const dir = "~/Desktop/hospital-it/src/scripts/mac";
const run = (name: string) => `sudo bash ${dir}/${name}`;
const script = (name: string, body: string): Script => ({ name, path: `src/scripts/mac/${name}`, body });

export const stages: Stage[] = [
  {
    id: 1,
    title: "Base setup",
    minutes: 45,
    tasks: ["Set the hostname", "Check network settings", "Check for system updates", "Install rsync and confirm the admin tools"],
    commands: [
      "mkdir -p ~/hospital-setup",
      "scutil --get LocalHostName > ~/hospital-setup/original_localhostname.txt",
      "sudo scutil --set HostName hospital-srv01",
      "sudo scutil --set LocalHostName hospital-srv01",
      "scutil --get HostName",
      "networksetup -listallnetworkservices",
      "ipconfig getifaddr en0",
      "netstat -rn -f inet | grep default",
      "networksetup -getinfo Wi-Fi",
      "sw_vers",
      "softwareupdate -l",
      "brew update",
      "brew install rsync",
      "brew list --versions rsync",
      "which dscl dseditgroup hdiutil pfctl launchctl ssh",
    ],
    expected: [
      "The saved file holds your original hostname and both hostname commands print hospital-srv01.",
      "The network commands show your Wi-Fi address, the default gateway and the router.",
      "softwareupdate lists pending updates or says no new software is available.",
      "brew prints an rsync 3.x version and which prints a path for all six tools.",
    ],
  },
  {
    id: 2,
    title: "Users and groups",
    minutes: 45,
    tasks: ["Create doctors, nurses and hosp_admin groups", "Create six standard sample users with a password", "Keep every home folder private"],
    scripts: [script("create_users.sh", createUsers), script("remove_users.sh", removeUsers)],
    commands: [
      run("create_users.sh"),
      "dscl . -read /Groups/doctors GroupMembership",
      "dscl . -read /Groups/nurses GroupMembership",
      "dscl . -read /Groups/hosp_admin GroupMembership",
      "id dr_asha",
      "id nurse_meera",
      "dseditgroup -o checkmember -m nurse_meera admin",
      "ls -ld /Users/dr_asha /Users/nurse_meera /Users/admin_priya",
      "sudo -u nurse_meera whoami",
    ],
    expected: [
      "The script reports each group and user as created and prints the three membership lines.",
      "id shows uid 803 for nurse_meera with the nurses group in its list.",
      "checkmember says no, so the sample users are not macOS administrators.",
      "Each home folder shows drwx------ and the last command prints nurse_meera.",
    ],
  },
  {
    id: 3,
    title: "Storage and ACL folders",
    minutes: 90,
    tasks: ["Create a 2 GB disk image volume", "Mount it at /Volumes/hospital with ownership on", "Create the four folders", "Apply the ACLs"],
    scripts: [script("setup_storage.sh", setupStorage), script("teardown_storage.sh", teardownStorage)],
    commands: [
      run("setup_storage.sh"),
      "diskutil info /Volumes/hospital | grep -i -E 'owners|file system'",
      "ls -led /Volumes/hospital/*",
      "sudo -u nurse_meera touch /Volumes/hospital/patient-records/test.txt",
      "echo 'Patient 001 admitted 2026-11-09' | sudo -u dr_asha tee /Volumes/hospital/patient-records/patient001.txt",
      "sudo -u nurse_meera cat /Volumes/hospital/patient-records/patient001.txt",
      "sudo -u admin_priya ls /Volumes/hospital/patient-records",
      "sudo -u dr_asha ls /Volumes/hospital/billing",
    ],
    expected: [
      "diskutil shows an APFS file system and Owners Enabled.",
      "Each folder shows drwx------ root wheel with numbered ACL lines for its groups.",
      "The nurse cannot write to patient-records and gets Permission denied.",
      "The doctor can write and the nurse can read the file back.",
      "The admin and the doctor are denied on the folders they should not see.",
    ],
  },
  {
    id: 4,
    title: "Automation and backup",
    minutes: 90,
    tasks: ["Backup script with dated archives and a checksum", "Disk usage script with an 80% warning", "Schedule both with launchd", "Verify backup integrity"],
    scripts: [
      script("install_automation.sh", installAutomation),
      script("hospital_backup.sh", hospitalBackup),
      script("hospital_verify.sh", hospitalVerify),
      script("hospital_disk_check.sh", hospitalDiskCheck),
      script("uninstall_automation.sh", uninstallAutomation),
    ],
    commands: [
      run("install_automation.sh"),
      "sudo launchctl list | grep hospital",
      "sudo launchctl kickstart -k system/com.hospital.backup",
      "sudo cat /var/log/hospital-backup.log",
      "sudo ls -l /Users/Shared/hospital-backups",
      "sudo /usr/local/hospital/bin/hospital_verify.sh",
      "sudo /usr/local/hospital/bin/hospital_disk_check.sh",
      "sudo /usr/local/hospital/bin/hospital_disk_check.sh 1",
    ],
    expected: [
      "launchctl lists com.hospital.backup and com.hospital.diskcheck.",
      "The log shows Backup created and Backup verified, and the backup folder holds the archive and its .sha256 file.",
      "verify prints OK, Archive readable and the file count.",
      "The disk check prints OK lines, and with a limit of 1 it prints WARNING lines.",
    ],
  },
  {
    id: 5,
    title: "Security",
    minutes: 60,
    tasks: ["Firewall: SSH only, from the local network", "Disable root SSH login", "Limit SSH to listed users", "Re-check every permission"],
    scripts: [script("firewall.sh", firewall), script("harden_ssh.sh", hardenSsh), script("permission_audit.sh", permissionAudit)],
    commands: [
      run("firewall.sh") + " check",
      run("firewall.sh") + " on",
      run("firewall.sh") + " status",
      "sudo systemsetup -setremotelogin on",
      run("harden_ssh.sh") + " apply",
      run("harden_ssh.sh") + " status",
      "ssh -o PubkeyAuthentication=no dr_asha@localhost whoami",
      "ssh -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 root@localhost",
      run("permission_audit.sh"),
    ],
    expected: [
      "The firewall status shows Enabled, a block rule and an SSH rule limited to your local network.",
      "harden_ssh status lists permitrootlogin no or shows the config file when sshd -T gives no output.",
      "The sample user logs in and prints dr_asha, and root gets Permission denied.",
      "The audit prints PASS on every line and ends with All checks passed.",
    ],
  },
  {
    id: 6,
    title: "Testing, recovery and demo",
    minutes: 90,
    tasks: ["Test every role against every folder", "Delete and restore the patient records", "Simulate and fix a storage failure", "Rehearse the demo"],
    scripts: [script("hospital_restore.sh", hospitalRestore), script("role_tests.sh", roleTests), script("collect_evidence.sh", collectEvidence)],
    commands: [
      run("role_tests.sh"),
      "sudo launchctl kickstart -k system/com.hospital.backup",
      "sudo tail -n 2 /var/log/hospital-backup.log",
      "sudo /usr/local/hospital/bin/hospital_verify.sh",
      "sudo rm -rf /Volumes/hospital/patient-records",
      "sudo ls /Volumes/hospital",
      run("hospital_restore.sh"),
      "sudo ls -led /Volumes/hospital/patient-records",
      "sudo -u nurse_meera cat /Volumes/hospital/patient-records/patient001.txt",
      run("role_tests.sh"),
      "sudo hdiutil detach /Volumes/hospital",
      "sudo /usr/local/hospital/bin/hospital_disk_check.sh",
      run("setup_storage.sh"),
      "sudo /usr/local/hospital/bin/hospital_disk_check.sh",
      run("collect_evidence.sh"),
    ],
    expected: [
      "The role table shows ok in every cell and ends with All role checks passed.",
      "After the delete, ls shows only three folders. The restore verifies the backup, restores the files and re-applies the ACLs.",
      "The nurse can read the restored file and the role tests pass again.",
      "The disk check warns when the volume is gone and returns to OK after setup_storage remounts it.",
      "collect_evidence prints PASS or FAIL for every check and saves the real output for the Evidence page.",
    ],
  },
];

export const schedule = [
  { job: "Hospital data backup", trigger: "launchd calendar 02:00", meaning: "Every day at 02:00" },
  { job: "Disk usage check", trigger: "launchd interval 3600 s", meaning: "Every hour" },
];

export const faqs: { q: string; a: string }[] = [
  {
    q: "What is this project?",
    a: "A server setup for a hospital IT department. Doctors, nurses and administration staff each get their own accounts and only the folder access their job needs, with scheduled backups, a firewall and hardened SSH.",
  },
  {
    q: "Why does it run on macOS and not Linux?",
    a: "It was built and tested on a Mac. Every Linux task has a macOS equivalent: dscl and dseditgroup replace useradd and groupadd, a disk image replaces LVM, chmod +a ACLs replace setfacl, launchd replaces cron and pf replaces ufw. The README lists the Linux and Windows commands too.",
  },
  {
    q: "What is an ACL?",
    a: "An Access Control List adds permission rules on top of the normal owner, group and others model. It lets one folder give doctors read and write, nurses read only, and administration nothing.",
  },
  {
    q: "What replaces LVM for storage?",
    a: "A 2 GB sparse disk image mounted at /Volumes/hospital. It is a separate volume with its own file system, it can be resized, and ownership is switched on so permissions and ACLs apply.",
  },
  {
    q: "How are backups handled?",
    a: "A launchd job runs every day at 02:00 and archives all four folders into a dated tar.gz file with a SHA-256 checksum. The checksum is verified right away and the last seven backups are kept. The restore script verifies the archive again before it restores anything.",
  },
  {
    q: "How is remote access secured?",
    a: "The pf firewall blocks incoming connections except SSH from the local network. SSH has root login off, three password tries, a 60 second login window and an allow list of named users. macOS also keeps its own SSH access group, and the script adds the allowed users to it.",
  },
  {
    q: "Why is the administration group called hosp_admin?",
    a: "macOS already has a group named admin that gives full administrator rights. Putting hospital staff in it would make them administrators of the whole Mac, so the hospital group has a different name.",
  },
  {
    q: "Can I run this on Linux or Windows?",
    a: "Yes. The README has a Linux (Ubuntu) section and a Windows PowerShell section for every stage.",
  },
  {
    q: "Where does the Evidence page get its data?",
    a: "From a script. collect_evidence.sh runs the real checks on your Mac, saves each command with its real output and a PASS or FAIL result into public/evidence.json, and the console reads that file. A web page cannot run commands itself, so run the script again to refresh the page.",
  },
  {
    q: "How do I undo everything?",
    a: "Run remove_users.sh, teardown_storage.sh, uninstall_automation.sh, firewall.sh off and harden_ssh.sh remove, then turn Remote Login off with systemsetup. The README lists the exact commands.",
  },
  {
    q: "Where is my console account stored?",
    a: "Console accounts are stored in your own browser only. Clearing site data removes them.",
  },
];
