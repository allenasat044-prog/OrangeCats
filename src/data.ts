import createUsers from "./scripts/create_users.sh?raw";

export type Role = "doctors" | "nurses" | "admin";
export type Level = "rw" | "r" | "none";

export const roles: { id: Role; label: string; duty: string }[] = [
  { id: "doctors", label: "Doctors", duty: "Read and edit patient records and read nursing notes." },
  { id: "nurses", label: "Nurses", duty: "Read patient records and read and write nursing notes." },
  { id: "admin", label: "Administration", duty: "Manage billing and announcements with no access to medical files." },
];

export const folders: { id: string; label: string; access: Record<Role, Level> }[] = [
  { id: "patient-records", label: "Patient Records", access: { doctors: "rw", nurses: "r", admin: "none" } },
  { id: "nursing-notes", label: "Nursing Notes", access: { doctors: "r", nurses: "rw", admin: "none" } },
  { id: "billing", label: "Billing", access: { doctors: "none", nurses: "none", admin: "rw" } },
  { id: "announcements", label: "Announcements", access: { doctors: "r", nurses: "r", admin: "rw" } },
];

export const modeFor: Record<Level, string> = { rw: "rwx", r: "r-x", none: "---" };

export type Stage = {
  id: number;
  title: string;
  minutes: number;
  tasks: string[];
  script?: { name: string; path: string; body: string };
  commands?: string[];
  expected?: string[];
};

export const stages: Stage[] = [
  {
    id: 1,
    title: "Base setup",
    minutes: 45,
    tasks: ["Set the hostname", "Check network settings", "Update the system", "Install acl, lvm2, openssh-server, ufw, rsync"],
    commands: [
      "sudo hostnamectl set-hostname hospital-srv01",
      "hostnamectl",
      "ip -br addr",
      "ip route",
      "sudo apt update",
      "sudo apt upgrade -y",
      "sudo apt install -y acl lvm2 openssh-server ufw rsync",
      "dpkg -s acl lvm2 openssh-server ufw rsync | grep -E '^(Package|Status)'",
    ],
    expected: [
      "hostnamectl shows the static hostname hospital-srv01.",
      "ip -br addr shows your interface with an IP address and ip route shows a default gateway.",
      "The final command lists all five packages with status install ok installed.",
    ],
  },
  {
    id: 2,
    title: "Users and groups",
    minutes: 45,
    tasks: ["Create doctors, nurses and admin groups", "Create sample users with passwords", "Script the user creation"],
    script: { name: "create_users.sh", path: "~/hospital-setup/create_users.sh", body: createUsers },
    commands: [
      "chmod +x ~/hospital-setup/create_users.sh",
      "sudo ~/hospital-setup/create_users.sh",
      "getent group doctors nurses admin",
      "id dr_asha",
      "id nurse_meera",
      "id admin_priya",
      "sudo chage -l dr_asha",
      "ls -ld /home/dr_asha /home/nurse_meera /home/admin_priya",
      "sudo su - nurse_meera -c 'whoami'",
    ],
    expected: [
      "The script reports each group and user as created and then prints the three group lines with their members.",
      "id shows each user in a private group plus its role group, for example nurse_meera in nurses.",
      "chage -l shows a maximum of 90 days between password changes.",
      "Each home directory shows drwx------ so users cannot read each other's files.",
      "The last command prints nurse_meera.",
    ],
  },
  {
    id: 3,
    title: "Storage and ACL folders",
    minutes: 90,
    tasks: ["Create LVM volume", "Mount it at /hospital", "Create the four folders", "Apply ACLs"],
  },
  {
    id: 4,
    title: "Automation and backup",
    minutes: 90,
    tasks: ["Backup script with dated archives", "Disk usage script with 80% warning", "Schedule both with cron", "Verify backup integrity"],
  },
  {
    id: 5,
    title: "Security",
    minutes: 60,
    tasks: ["Enable firewall for SSH only", "Disable root SSH login", "Limit SSH to allowed users", "Re-check permissions"],
  },
  {
    id: 6,
    title: "Testing, recovery and demo",
    minutes: 90,
    tasks: ["Delete and restore patient records", "Test every role", "Write the report", "Rehearse the demo"],
  },
];

export const schedule = [
  { job: "Patient records backup", cron: "0 2 * * *", meaning: "Every day at 02:00" },
  { job: "Disk usage check", cron: "0 * * * *", meaning: "Every hour" },
];

export const faqs: { q: string; a: string }[] = [
  {
    q: "What is this project?",
    a: "A Linux server set up for a hospital IT department. Doctors, nurses and administration staff each get their own accounts and only the folder access their job needs.",
  },
  {
    q: "What is an ACL?",
    a: "An Access Control List adds permission rules on top of the normal owner, group and others model. It lets one folder give doctors read and write, nurses read only, and admin nothing.",
  },
  {
    q: "Why use LVM for storage?",
    a: "LVM lets you grow a volume later without reformatting. If the hospital stores more records, you extend the logical volume and the filesystem while it stays mounted.",
  },
  {
    q: "How are backups handled?",
    a: "A shell script archives the patient records into a dated file, and cron runs it every night at 02:00. A checksum comparison confirms the archive is not corrupted, and a restore test proves the data comes back.",
  },
  {
    q: "How is remote access secured?",
    a: "SSH is the only service the firewall allows. Root login is disabled and only listed users can connect.",
  },
  {
    q: "Which Linux does the guide use?",
    a: "Ubuntu Server. The package commands use apt. On Red Hat based systems replace apt with dnf and ufw with firewalld.",
  },
  {
    q: "Where is my account stored?",
    a: "Accounts are stored in your own browser only. Clearing site data removes them.",
  },
];
