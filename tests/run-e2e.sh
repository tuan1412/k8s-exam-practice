#!/usr/bin/env bash
# E2E test of the labs themselves. For each question:
#   1) setup -> validate must FAIL and score 0 checks (no free points)
#   2) common wrong answer -> validate must FAIL (trap is caught)
#   3) setup again -> correct answer -> validate must fully PASS
# Usage: tests/run-e2e.sh [-m cka/mock-01] <question...|all>
# Env: INCLUDE_DESTRUCTIVE=1 (also Q8), KEEP=1 (skip final cleanup)
set -uo pipefail
source "$(dirname "$0")/../scripts/lib/common.sh"

mock="$DEFAULT_MOCK"
if [ "${1:-}" == "-m" ]; then mock="$2"; shift 2; fi
MOCK_DIR="$REPO_ROOT/$mock"; T_DIR="$REPO_ROOT/tests/$mock"
[ $# -ge 1 ] || { echo "Usage: $0 [-m cka/mock-01] <question...|all>"; exit 1; }
LOG_DIR="${LOG_DIR:-/tmp/k8s-exam-practice-e2e}"; mkdir -p "$LOG_DIR"

if [ "$1" == "all" ]; then dirs=$(list_questions); else dirs=$(for q in "$@"; do resolve_question "$q"; done); fi

validate_rc() { bash "$1/validate.bash" >> "$2" 2>&1; echo $?; }
summary=""; failed=0
for d in $dirs; do
  n=$(basename "$d"); log="$LOG_DIR/$n.log"; : > "$log"
  if [ -f "$d/DESTRUCTIVE" ] && [ "${INCLUDE_DESTRUCTIVE:-0}" != "1" ]; then
    summary+=$(printf '%-38s %s' "$n" "SKIP (destructive)")$'\n'; continue
  fi
  if [ ! -f "$T_DIR/solutions/$n.sh" ]; then
    summary+=$(printf '%-38s %s' "$n" "SKIP (no solution script)")$'\n'; continue
  fi
  echo "$(c_bold "== $n")  (log: $log)"
  { echo "### cleanup+setup"; bash "$d/cleanup.bash"; bash "$d/LabSetUp.bash"; } >> "$log" 2>&1
  echo "### validate (untouched)" >> "$log"; r_empty=$(validate_rc "$d" "$log")
  p_empty=$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -oE 'RESULT [0-9]+/' | tail -1 | grep -oE '[0-9]+')
  r_wrong="-"
  if [ -f "$T_DIR/wrong/$n.sh" ]; then
    { echo "### wrong answer"; bash "$T_DIR/wrong/$n.sh"; } >> "$log" 2>&1
    echo "### validate (wrong answer)" >> "$log"; r_wrong=$(validate_rc "$d" "$log")
  fi
  { echo "### cleanup+setup"; bash "$d/cleanup.bash"; bash "$d/LabSetUp.bash"; echo "### solution"; bash "$T_DIR/solutions/$n.sh"; } >> "$log" 2>&1
  echo "### validate (correct answer)" >> "$log"; r_ok=$(validate_rc "$d" "$log")
  [ "${KEEP:-0}" == "1" ] || bash "$d/cleanup.bash" >> "$log" 2>&1

  ok=1; [ "$r_empty" -ne 0 ] && [ "${p_empty:-1}" -eq 0 ] || ok=0; [ "$r_wrong" == "-" ] || [ "$r_wrong" -ne 0 ] || ok=0; [ "$r_ok" -eq 0 ] || ok=0
  st=$([ $ok -eq 1 ] && c_green OK || c_red FAIL); [ $ok -eq 1 ] || failed=$((failed+1))
  line=$(printf '%-38s %s  untouched:%s-fail/%s-scored  wrong:%s-fail  correct:%s-fail' "$n" "$st" "$r_empty" "${p_empty:-?}" "$r_wrong" "$r_ok")
  echo "$line"; summary+="$line"$'\n'
done
echo; echo "$(c_bold "== E2E SUMMARY") (numbers = failed checks; 'correct' must be 0, the others > 0)"; printf '%s' "$summary"
exit $failed
