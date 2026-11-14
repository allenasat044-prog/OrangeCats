#!/bin/bash
# MJ Fix - Stage 1 (macOS): "What if we change a permission? How does the system react?"
# Break -> Observe -> Detect -> Restore.  Matches the OrangeCats macOS build
# (/Volumes/hospital, groups doctors/nurses/hosp_admin, root:wheel, chmod +a ACLs).
# Usage: sudo bash mj_fix_stage1_permissions.sh baseline|test|break N|restore|demo|status
set -u

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

VOLUME="${VOLUME:-/Volumes/hospital}"
FOLDERS=(patient-records nursing-notes billing announcements)
G_DOC=doctors; G_NUR=nurses; G_ADM=hosp_admin

# same ACL strings as setup_storage.sh
RW="list,search,add_file,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,file_inherit,directory_inherit"
R="list,search,readattr,readextattr,file_inherit,directory_inherit"
WRITE_ONLY="add_file,add_subdirectory,delete_child"

# user | patient-records | nursing-notes | billing | announcements
EXPECT=(
  "dr_asha|rw|r|-|r"
  "dr_ravi|rw|r|-|r"
  "nurse_meera|r|rw|-|r"
  "nurse_john|r|rw|-|r"
  "admin_priya|-|-|rw|rw"
  "admin_kiran|-|-|rw|rw"
)

if [ ! -d "$VOLUME" ]; then
  echo "Volume $VOLUME not found. Run setup_storage.sh first." >&2
  exit 1
fi

flush() { dsmemberutil flushcache > /dev/null 2>&1 || true; }

setacl() { # folder group level
  case "$3" in
    rw) chmod +a "group:$2 allow $RW" "$VOLUME/$1" ;;
    r)  chmod +a "group:$2 allow $R"  "$VOLUME/$1" ;;
  esac
}

baseline() {
  for f in "${FOLDERS[@]}"; do
    mkdir -p "$VOLUME/$f"
    chown root:wheel "$VOLUME/$f"
    chmod 700 "$VOLUME/$f"
    chmod -N "$VOLUME/$f"
  done
  setacl patient-records "$G_DOC" rw; setacl patient-records "$G_NUR" r
  setacl nursing-notes   "$G_DOC" r;  setacl nursing-notes   "$G_NUR" rw
  setacl billing         "$G_ADM" rw
  setacl announcements   "$G_DOC" r;  setacl announcements   "$G_NUR" r; setacl announcements "$G_ADM" rw
  dseditgroup -o edit -d nurse_john -t user "$G_DOC" > /dev/null 2>&1 || true
  flush
  echo "Baseline (correct least-privilege state) applied."
}

access() { # user dir -> rw | r | w | -
  u="$1"; d="$2"; r=0; w=0; p="$2/.mj_probe_$1"
  if sudo -u "$u" ls "$d" > /dev/null 2>&1; then r=1; fi
  if sudo -u "$u" touch "$p" > /dev/null 2>&1; then w=1; rm -f "$p"; fi
  if [ "$r$w" = "11" ]; then echo rw
  elif [ "$r" = 1 ]; then echo r
  elif [ "$w" = 1 ]; then echo w
  else echo "-"; fi
}

BAD=0
matrix() {
  BAD=0
  printf '%-13s' user
  for f in "${FOLDERS[@]}"; do printf '%-30s' "$f"; done
  echo
  for row in "${EXPECT[@]}"; do
    IFS='|' read -r u e1 e2 e3 e4 <<< "$row"
    ex=("$e1" "$e2" "$e3" "$e4")
    printf '%-13s' "$u"
    i=0
    for f in "${FOLDERS[@]}"; do
      a="$(access "$u" "$VOLUME/$f")"
      if [ "$a" = "${ex[$i]}" ]; then
        printf '%-30s' "$a  OK"
      else
        printf '%-30s' "$a  <-- WRONG(exp ${ex[$i]})"
        BAD=$((BAD + 1))
      fi
      i=$((i + 1))
    done
    echo
  done
  if [ "$BAD" -gt 0 ]; then
    echo ">> AUDIT: FAIL - $BAD access(es) differ from policy."
  else
    echo ">> AUDIT: PASS - all access matches policy."
  fi
}

audit_modes() { # every folder must stay drwx------ root:wheel
  for f in "${FOLDERS[@]}"; do
    meta="$(stat -f '%Sp %Su:%Sg' "$VOLUME/$f" 2> /dev/null || true)"
    if [ "$meta" = "drwx------ root:wheel" ]; then
      echo "PASS: $f is $meta"
    else
      echo "FAIL: $f is '$meta' (expected drwx------ root:wheel)"
      BAD=$((BAD + 1))
    fi
  done
}

describe() {
  case "$1" in
    1) echo "Scenario 1: nurses given WRITE on patient-records (r -> rw)" ;;
    2) echo "Scenario 2: hosp_admin (billing staff) given READ on patient-records (none -> r)" ;;
    3) echo "Scenario 3: billing set to chmod 777 (everyone)" ;;
    4) echo "Scenario 4: nurse_john added to doctors group (privilege via group)" ;;
    5) echo "Scenario 5: doctors lose WRITE on patient-records (rw -> r)" ;;
  esac
}

break_it() {
  case "$1" in
    1) setacl patient-records "$G_NUR" rw ;;
    2) setacl patient-records "$G_ADM" r ;;
    3) chmod 777 "$VOLUME/billing" ;;
    4) dseditgroup -o edit -a nurse_john -t user "$G_DOC"; flush ;;
    5) chmod +a# 0 "group:$G_DOC deny $WRITE_ONLY" "$VOLUME/patient-records" ;;
    *) echo "Choose scenario 1-5"; exit 1 ;;
  esac
}

run_test() { matrix; audit_modes; }

demo() {
  echo "=== BEFORE: correct state ==="
  baseline > /dev/null
  run_test
  for n in 1 2 3 4 5; do
    echo
    echo "------------------------------------------------------------"
    describe "$n"
    read -rp "Press Enter to apply this change... " _
    break_it "$n"
    echo "--- ACLs / mode after the change ---"
    ls -led "$VOLUME/patient-records" "$VOLUME/billing"
    echo "=== SYSTEM REACTION ==="
    run_test
    read -rp "Press Enter to RESTORE... " _
    baseline > /dev/null
    run_test
  done
  echo
  echo "Demo complete: every change took effect instantly, was detected, and was reverted."
}

case "${1:-test}" in
  baseline|restore) baseline; run_test ;;
  test)   run_test ;;
  break)  describe "${2:-0}"; break_it "${2:-0}"; run_test ;;
  demo)   demo ;;
  status) ls -led "$VOLUME"/* ;;
  *) echo "Usage: sudo bash $0 baseline|test|break N|restore|demo|status"; exit 1 ;;
esac
