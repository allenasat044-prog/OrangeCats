#!/usr/bin/env bash
# MJ Fix - Stage 1: "What if we change a permission? How does the system react?"
# Ubuntu. Break -> Observe -> Detect -> Restore.
# Usage: sudo bash mj_fix_stage1_permissions.sh baseline|test|break N|restore|demo|status
set -u
[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }

ROOT="${ROOT:-/hospital}"
FOLDERS=(patient-records nursing-notes billing announcements)
# user | patient-records | nursing-notes | billing | announcements
EXPECT=(
  "dr_asha|rw|r|-|r"
  "dr_ravi|rw|r|-|r"
  "nurse_meera|r|rw|-|r"
  "nurse_john|r|rw|-|r"
  "admin_priya|-|-|rw|rw"
  "admin_kiran|-|-|rw|rw"
)
G_DOC=doctors; G_NUR=nurses; G_ADM=admin

acl() { # folder, acl-spec  (sets access + default ACL)
  setfacl -m "$2" "$ROOT/$1"; setfacl -d -m "$2" "$ROOT/$1"
}

baseline() {
  for f in "${FOLDERS[@]}"; do
    d="$ROOT/$f"; mkdir -p "$d"
    setfacl -R -b "$d"; chown root:root "$d"; chmod 770 "$d"
  done
  acl patient-records "g:$G_DOC:rwx,g:$G_NUR:r-x"
  acl nursing-notes   "g:$G_DOC:r-x,g:$G_NUR:rwx"
  acl billing         "g:$G_ADM:rwx"
  acl announcements   "g:$G_DOC:r-x,g:$G_NUR:r-x,g:$G_ADM:rwx"
  gpasswd -d nurse_john "$G_DOC" > /dev/null 2>&1 || true
  echo "Baseline (correct least-privilege state) applied."
}

access() { # user dir -> rw | r | -
  local u="$1" d="$2" r=0 w=0 p="$2/.mj_probe_$1"
  sudo -u "$u" ls "$d" > /dev/null 2>&1 && r=1
  if sudo -u "$u" touch "$p" > /dev/null 2>&1; then w=1; rm -f "$p"; fi
  if   [[ $r$w == 11 ]]; then echo rw
  elif [[ $r == 1 ]];    then echo r
  elif [[ $w == 1 ]];    then echo w
  else echo "-"; fi
}

BAD=0
matrix() {
  BAD=0
  printf '%-13s' user; for f in "${FOLDERS[@]}"; do printf '%-30s' "$f"; done; echo
  for row in "${EXPECT[@]}"; do
    IFS='|' read -r u e1 e2 e3 e4 <<< "$row"; ex=("$e1" "$e2" "$e3" "$e4")
    printf '%-13s' "$u"; i=0
    for f in "${FOLDERS[@]}"; do
      a="$(access "$u" "$ROOT/$f")"
      if [[ "$a" == "${ex[$i]}" ]]; then printf '%-30s' "$a  OK"
      else printf '%-30s' "$a  <-- WRONG(exp ${ex[$i]})"; BAD=$((BAD+1)); fi
      i=$((i+1))
    done; echo
  done
  if (( BAD )); then echo ">> AUDIT: FAIL - $BAD access(es) differ from policy."
  else echo ">> AUDIT: PASS - all access matches policy."; fi
}

audit_modes() { # detects loose modes like 777
  for f in "${FOLDERS[@]}"; do
    m="$(stat -c '%a' "$ROOT/$f")"
    # with ACLs the group bits show the mask; 'other' must be 0
    if [[ "${m: -1}" != 0 ]]; then echo "FAIL: $f mode is $m (others have access)"; BAD=$((BAD+1))
    else echo "PASS: $f mode $m, others have no access"; fi
  done
}

describe() {
  case "$1" in
    1) echo "Scenario 1: nurses given WRITE on patient-records (r -> rw)";;
    2) echo "Scenario 2: admin (billing staff) given READ on patient-records (none -> r)";;
    3) echo "Scenario 3: billing set to chmod 777 (everyone)";;
    4) echo "Scenario 4: nurse_john added to doctors group (privilege via group)";;
    5) echo "Scenario 5: doctors lose WRITE on patient-records (rw -> r)";;
  esac
}

break_it() {
  case "$1" in
    1) setfacl -m "g:$G_NUR:rwx" "$ROOT/patient-records";;
    2) setfacl -m "g:$G_ADM:r-x" "$ROOT/patient-records";;
    3) chmod 777 "$ROOT/billing";;
    4) usermod -aG "$G_DOC" nurse_john;;
    5) setfacl -m "g:$G_DOC:r-x" "$ROOT/patient-records";;
    *) echo "Choose scenario 1-5"; exit 1;;
  esac
}

run_test() { matrix; audit_modes; }

demo() {
  echo "=== BEFORE: correct state ==="; baseline > /dev/null; run_test
  for n in 1 2 3 4 5; do
    echo; echo "------------------------------------------------------------"
    describe "$n"; read -rp "Press Enter to apply this change... " _
    break_it "$n"
    echo "--- getfacl patient-records / billing ---"
    getfacl -p "$ROOT/patient-records" 2>/dev/null | grep -E 'group:|other'
    stat -c '%n %a' "$ROOT/billing"
    echo "=== SYSTEM REACTION ==="; run_test
    read -rp "Press Enter to RESTORE... " _
    baseline > /dev/null; run_test
  done
  echo; echo "Demo complete: every change took effect instantly, was detected, and was reverted."
}

case "${1:-test}" in
  baseline|restore) baseline; run_test;;
  test)   run_test;;
  break)  describe "${2:-0}"; break_it "${2:-0}"; run_test;;
  demo)   demo;;
  status) for f in "${FOLDERS[@]}"; do echo "== $f"; getfacl -p "$ROOT/$f" 2>/dev/null; done;;
  *) echo "Usage: sudo bash $0 baseline|test|break N|restore|demo|status"; exit 1;;
esac
