#!/bin/bash
# MJ Fix - Stage 1 (macOS): permission-change demo, per-role demos, and "make it permanent".
# Matches the OrangeCats macOS build (/Volumes/hospital, hosp_admin, root:wheel, chmod +a ACLs).
# Run: sudo bash mj_fix_stage1_permissions.sh help
VOLUME="${VOLUME:-/Volumes/hospital}"
VOL="$VOLUME"
G_DOC=doctors; G_NUR=nurses; G_ADM=hosp_admin
DEFAULT_MODE=700
RW="list,search,add_file,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,file_inherit,directory_inherit"
R="list,search,readattr,readextattr,file_inherit,directory_inherit"
WRITE_ONLY="add_file,add_subdirectory,delete_child"

p_reset_dir()  { d="$VOL/$1"; mkdir -p "$d"; chown root:wheel "$d"; chmod "$DEFAULT_MODE" "$d"; chmod -N "$d"; }
p_set_mode()   { chmod "$2" "$VOL/$1"; }
p_grant()      { case "$3" in rw) chmod +a "group:$2 allow $RW" "$VOL/$1" ;; r) chmod +a "group:$2 allow $R" "$VOL/$1" ;; esac; }
p_member_add() { dseditgroup -o edit -a "$1" -t user "$2" > /dev/null 2>&1; }
p_member_del() { dseditgroup -o edit -d "$1" -t user "$2" > /dev/null 2>&1 || true; }
p_flush()      { dsmemberutil flushcache > /dev/null 2>&1 || true; }
p_check_mode() { # folder expected_mode
  meta="$(stat -f '%Lp %Su:%Sg' "$VOL/$1" 2> /dev/null || true)"
  if [ "$meta" = "$2 root:wheel" ]; then echo "PASS: $1 is $meta"
  else echo "FAIL: $1 is '$meta' (policy expects '$2 root:wheel')"; BAD=$((BAD + 1)); fi; }
p_show()       { ls -led "$VOL/$1"; }
p_break5()     { chmod +a# 0 "group:$G_DOC deny $WRITE_ONLY" "$VOL/patient-records"; }

# ===================== common body (bash 3.2 compatible) =====================
set -u
if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script with sudo." >&2
  exit 1
fi
cd / || exit 1

FOLDERS="patient-records nursing-notes billing announcements"
USERS="dr_asha:$G_DOC dr_ravi:$G_DOC nurse_meera:$G_NUR nurse_john:$G_NUR admin_priya:$G_ADM admin_kiran:$G_ADM"
POLICY_DIR="${MJ_POLICY_DIR:-/etc/mj_fix}"
POLICY="$POLICY_DIR/policy.conf"
NEW="$POLICY.new"
LOG="$POLICY_DIR/changes.log"

if [ -t 1 ]; then GRN=$'\033[32m'; RED=$'\033[31m'; RST=$'\033[0m'; else GRN=""; RED=""; RST=""; fi

if [ ! -d "$VOL" ]; then
  echo "$VOL not found. Run the storage setup first." >&2
  exit 1
fi

# ---------- policy (the "normal form" of the system) ----------
default_policy() {
  cat << POL
# MJ Fix policy.  folder|$G_DOC|$G_NUR|$G_ADM   (levels: rw, r, none)
# optional lines:  mode|folder|octal    member|user|group
patient-records|rw|r|none
nursing-notes|r|rw|none
billing|none|none|rw
announcements|r|r|rw
POL
}

ensure_policy() {
  mkdir -p "$POLICY_DIR"
  [ -f "$POLICY" ] || default_policy > "$POLICY"
  chmod 644 "$POLICY"
}

log_change() { mkdir -p "$POLICY_DIR"; echo "$(date '+%Y-%m-%d %H:%M:%S') | ${SUDO_USER:-root} | $*" >> "$LOG"; }

col_of()   { case "$1" in "$G_DOC") echo 2 ;; "$G_NUR") echo 3 ;; "$G_ADM") echo 4 ;; esac; }
level_of() { awk -F'|' -v f="$1" -v c="$2" '$1==f { print $c }' "$POLICY"; }
mode_of()  { m="$(awk -F'|' -v f="$1" '$1=="mode" && $2==f { print $3 }' "$POLICY" | tail -n 1)"; echo "${m:-$DEFAULT_MODE}"; }

base_group() { for pair in $USERS; do if [ "${pair%%:*}" = "$1" ]; then echo "${pair##*:}"; fi; done; }
user_groups() { base_group "$1"; awk -F'|' -v u="$1" '$1=="member" && $2==u { print $3 }' "$POLICY"; }

expected_access() { # user folder -> rw | r | -
  best="-"
  for g in $(user_groups "$1"); do
    l="$(level_of "$2" "$(col_of "$g")")"
    if [ "$l" = rw ]; then best=rw
    elif [ "$l" = r ] && [ "$best" != rw ]; then best=r; fi
  done
  echo "$best"
}

apply_policy() {
  ensure_policy
  for f in $FOLDERS; do
    p_reset_dir "$f"
    p_set_mode "$f" "$(mode_of "$f")"
    for g in $G_DOC $G_NUR $G_ADM; do
      l="$(level_of "$f" "$(col_of "$g")")"
      case "$l" in rw | r) p_grant "$f" "$g" "$l" ;; esac
    done
  done
  for pair in $USERS; do
    u="${pair%%:*}"; base="${pair##*:}"
    for g in $G_DOC $G_NUR $G_ADM; do
      if [ "$g" = "$base" ]; then continue; fi
      if grep -qx "member|$u|$g" "$POLICY"; then p_member_add "$u" "$g"; else p_member_del "$u" "$g"; fi
    done
  done
  p_flush
  echo "System configured from policy: $POLICY"
}

# ---------- testing against the policy ----------
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
  for f in $FOLDERS; do printf '%-30s' "$f"; done
  echo
  for pair in $USERS; do
    u="${pair%%:*}"
    printf '%-13s' "$u"
    for f in $FOLDERS; do
      a="$(access "$u" "$VOL/$f")"; e="$(expected_access "$u" "$f")"
      if [ "$a" = "$e" ]; then printf '%-30s' "$a  OK"
      else printf '%-30s' "$a  <-- WRONG(exp $e)"; BAD=$((BAD + 1)); fi
    done
    echo
  done
  if [ "$BAD" -gt 0 ]; then echo ">> AUDIT: ${RED}FAIL${RST} - $BAD access(es) differ from policy."
  else echo ">> AUDIT: ${GRN}PASS${RST} - all access matches policy."; fi
}

audit_modes() { for f in $FOLDERS; do p_check_mode "$f" "$(mode_of "$f")"; done; }
run_test() { matrix; audit_modes; }

# ---------- the five scenarios ----------
describe() {
  case "$1" in
    1) echo "Scenario 1: nurses given WRITE on patient-records (r -> rw)" ;;
    2) echo "Scenario 2: $G_ADM (billing staff) given READ on patient-records (none -> r)" ;;
    3) echo "Scenario 3: billing set to chmod 777 (everyone)" ;;
    4) echo "Scenario 4: nurse_john added to $G_DOC group (privilege via group)" ;;
    5) echo "Scenario 5: doctors lose WRITE on patient-records (rw -> r)" ;;
  esac
}

break_it() { # temporary, live change
  case "$1" in
    1) p_grant patient-records "$G_NUR" rw ;;
    2) p_grant patient-records "$G_ADM" r ;;
    3) chmod 777 "$VOL/billing" ;;
    4) p_member_add nurse_john "$G_DOC"; p_flush ;;
    5) p_break5 ;;
    *) echo "Choose scenario 1-5"; exit 1 ;;
  esac
}

set_level()  { awk -F'|' -v OFS='|' -v f="$1" -v c="$(col_of "$2")" -v l="$3" '$1==f { $c=l } { print }' "$NEW" > "$NEW.t" && mv "$NEW.t" "$NEW"; }
set_mode()   { grep -v "^mode|$1|" "$NEW" > "$NEW.t"; echo "mode|$1|$2" >> "$NEW.t"; mv "$NEW.t" "$NEW"; }
add_member() { grep -qx "member|$1|$2" "$NEW" || echo "member|$1|$2" >> "$NEW"; }

policy_edit() { # build the NEW policy for a scenario
  ensure_policy; cp "$POLICY" "$NEW"
  case "$1" in
    1) set_level patient-records "$G_NUR" rw ;;
    2) set_level patient-records "$G_ADM" r ;;
    3) set_mode billing 777 ;;
    4) add_member nurse_john "$G_DOC" ;;
    5) set_level patient-records "$G_DOC" r ;;
  esac
}

show_diff() { diff "$POLICY" "$NEW" | grep '^[<>]' | sed 's/^< /   was: /; s/^> /   now: /'; }

offer_permanent() { # returns 0 if made permanent
  echo
  echo "If made permanent, the policy of the WHOLE system changes like this:"
  policy_edit "$1"; show_diff
  if [ "$1" = 3 ]; then
    echo "${RED}WARNING: this opens billing to EVERY user. Not recommended for a hospital.${RST}"
    read -rp "Type CONFIRM to make it permanent, anything else to cancel: " ans || ans=""
    if [ "$ans" != CONFIRM ]; then rm -f "$NEW"; return 1; fi
  else
    read -rp "Do you want to make this change PERMANENT for the whole system? (yes/no) [no]: " ans || ans=""
    case "$ans" in y | Y | yes | YES | Yes) ;; *) rm -f "$NEW"; return 1 ;; esac
  fi
  cp "$POLICY" "$POLICY.prev"; mv "$NEW" "$POLICY"
  log_change "scenario $1 made permanent: $(describe "$1")"
  apply_policy
  echo "Permanent change applied. Re-checking against the NEW policy:"
  run_test
  echo "(Previous policy saved. Undo last change: sudo bash $0 undo | Factory defaults: sudo bash $0 reset)"
  return 0
}

demo() {
  echo "=== BEFORE: current policy ==="
  apply_policy > /dev/null; run_test
  for n in 1 2 3 4 5; do
    echo; echo "------------------------------------------------------------"
    describe "$n"
    read -rp "Press Enter to apply this change... " _ || true
    break_it "$n"
    echo "--- permissions after the change ---"
    p_show patient-records; p_show billing
    echo "=== SYSTEM REACTION ==="
    run_test
    if offer_permanent "$n"; then
      echo ">> $(describe "$n") is now the NEW NORMAL."
    else
      read -rp "Press Enter to RESTORE... " _ || true
      apply_policy > /dev/null; run_test
    fi
  done
  echo; echo "Demo complete. (Back to factory defaults any time: sudo bash $0 reset)"
}

# ---------- per-role demos: read / write / edit / delete ----------
primary_folder() { case "$(base_group "$1")" in "$G_DOC") echo patient-records ;; "$G_NUR") echo nursing-notes ;; *) echo billing ;; esac; }

expected_allowed() { # user action folder -> yes | no
  e="$(expected_access "$1" "$3")"
  case "$2" in
    list | read) if [ "$e" = r ] || [ "$e" = rw ]; then echo yes; else echo no; fi ;;
    *) if [ "$e" = rw ]; then echo yes; else echo no; fi ;;
  esac
}

run_action() { # user action folder verbose(0/1); returns the real exit code
  u="$1"; a="$2"; f="$3"; v="${4:-0}"; d="$VOL/$f"
  seed="$d/sample_record.txt"; victim="$d/delete_probe.txt"; new="$d/new_by_$u.txt"
  rm -f "$seed" "$victim" "$new"
  case "$a" in
    list)   cmd="ls $d" ;;
    read)   echo "Sample record: patient Ravi Kumar, hypertension" > "$seed"; cmd="cat $seed" ;;
    create) cmd="echo 'New entry written by $u' > $new" ;;
    edit)   echo "Sample record: patient Ravi Kumar, hypertension" > "$seed"; cmd="echo 'Edited by $u' >> $seed" ;;
    delete) echo "delete me" > "$victim"; cmd="rm $victim" ;;
    *) echo "Unknown action '$a' (use list|read|create|edit|delete)"; return 2 ;;
  esac
  out="$(sudo -u "$u" bash -c "$cmd" 2>&1)"; rc=$?
  if [ "$v" = 1 ]; then
    echo "\$ sudo -u $u bash -c \"$cmd\""
    if [ -n "$out" ]; then echo "$out"; fi
  fi
  rm -f "$seed" "$victim" "$new"
  return $rc
}

cmd_act() { # user action [folder]
  u="$1"; a="$2"; f="${3:-$(primary_folder "$u")}"
  if [ -z "$(base_group "$u")" ]; then echo "Unknown user $u"; exit 1; fi
  echo "=== $u ($(base_group "$u")) tries to $a in $f ==="
  run_action "$u" "$a" "$f" 1; rc=$?
  want="$(expected_allowed "$u" "$a" "$f")"
  if [ $rc -eq 0 ]; then got=yes; res="${GRN}ALLOWED${RST}"; else got=no; res="${RED}DENIED${RST}"; fi
  if [ "$got" = "$want" ]; then chk="matches policy"; else chk="${RED}DIFFERS from policy${RST}"; fi
  echo "RESULT: $res  ($chk)"
}

cmd_role() { # full story for one user
  u="$1"; pf="$(primary_folder "$u")"
  echo "########## ROLE DEMO: $u ($(base_group "$u")) ##########"
  echo "--- own area: $pf ---"
  for a in list read create edit delete; do cmd_act "$u" "$a" "$pf"; echo; done
  echo "--- same user trying the OTHER folders ---"
  for f in $FOLDERS; do
    if [ "$f" = "$pf" ]; then continue; fi
    for a in read create; do cmd_act "$u" "$a" "$f"; done
  done
}

cmd_roles() { # matrix for one or all users
  ALLBAD=0
  if [ -n "${1:-}" ]; then list="$1:x"; else list="$USERS"; fi
  for pair in $list; do
    u="${pair%%:*}"
    echo; echo "$u ($(base_group "$u"))"
    printf '  %-18s %-6s %-6s %-8s %-6s %-7s\n' folder LIST READ CREATE EDIT DELETE
    for f in $FOLDERS; do
      printf '  %-18s ' "$f"
      for a in list read create edit delete; do
        run_action "$u" "$a" "$f" 0; rc=$?
        want="$(expected_allowed "$u" "$a" "$f")"
        if [ $rc -eq 0 ]; then cell=yes; got=yes; else cell=NO; got=no; fi
        if [ "$got" != "$want" ]; then cell="$cell!"; ALLBAD=$((ALLBAD + 1)); fi
        printf '%-7s' "$cell"
      done
      echo
    done
  done
  echo; echo "(yes = allowed, NO = denied, ! = differs from policy)"
  if [ "$ALLBAD" -gt 0 ]; then echo ">> ROLES: ${RED}FAIL${RST} - $ALLBAD action(s) differ from policy."
  else echo ">> ROLES: ${GRN}PASS${RST} - every action matches policy."; fi
}

usage() {
cat << USE
MJ Fix - Stage 1   (sudo bash $0 <command>)

 Scenarios (change a permission, watch the system react)
  demo               guided demo of 5 scenarios; after each you are asked: make it PERMANENT?
  break N            apply scenario N (1-5) temporarily, then show the reaction
  permanent N        apply scenario N, show reaction, then ask to make it the new normal
  baseline|restore   re-apply the current policy (undo any temporary change)
  test               check every user x folder against the policy
 Policy (the "normal form")
  policy             show the active policy      log      show who changed what, and when
  undo               go back to the policy before the last permanent change
  reset              back to factory defaults
 Role demos
  role USER          full story: list/read/create/edit/delete in own folder + other folders
  act USER ACTION [FOLDER]   one action, e.g.  act dr_asha edit patient-records
                     ACTION = list | read | create | edit | delete
  roles [USER]       table of everything everyone can do
  status             show current ACLs
USE
}

case "${1:-help}" in
  baseline | restore) apply_policy; run_test ;;
  test)   ensure_policy; run_test ;;
  break)  ensure_policy; describe "${2:-0}"; break_it "${2:-0}"; run_test ;;
  permanent)
    ensure_policy; describe "${2:-0}"; break_it "${2:-0}"; run_test
    if ! offer_permanent "${2:-0}"; then echo "Not made permanent: restoring."; apply_policy > /dev/null; run_test; fi ;;
  demo)   ensure_policy; demo ;;
  policy) ensure_policy; cat "$POLICY"; echo; if default_policy | diff -q - "$POLICY" > /dev/null; then echo "(factory defaults)"; else echo "(CUSTOMISED - differs from factory defaults)"; fi ;;
  log)    if [ -f "$LOG" ]; then cat "$LOG"; else echo "No permanent changes recorded."; fi ;;
  undo)   if [ -f "$POLICY.prev" ]; then cp "$POLICY.prev" "$POLICY"; log_change "undo: previous policy restored"; apply_policy; run_test; else echo "Nothing to undo."; fi ;;
  reset)  mkdir -p "$POLICY_DIR"; [ -f "$POLICY" ] && cp "$POLICY" "$POLICY.prev"; default_policy > "$POLICY"; log_change "reset to factory defaults"; apply_policy; run_test ;;
  role)   ensure_policy; cmd_role "${2:?usage: role USER}" ;;
  act)    ensure_policy; cmd_act "${2:?usage: act USER ACTION [FOLDER]}" "${3:?usage: act USER ACTION [FOLDER]}" "${4:-}" ;;
  roles)  ensure_policy; cmd_roles "${2:-}" ;;
  status) for f in $FOLDERS; do p_show "$f"; done ;;
  *)      usage ;;
esac
