export const stages: { id: number; title: string }[] = [
  { id: 1, title: "Base setup" },
  { id: 2, title: "Users and groups" },
  { id: 3, title: "Storage and ACL folders" },
  { id: 4, title: "Automation and backup" },
  { id: 5, title: "Security" },
  { id: 6, title: "Testing, recovery and demo" },
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
