#!/usr/bin/env bash
# Library for each question's validate.bash. Sourced.
#   check "desc" <cmd...>       -> PASS if cmd exits 0
#   check_eq "desc" <actual> <expected>
#   guard / guard_eq            -> same, for "don't break X" checks that already pass right after
#                                  setup: they only earn points once a task check passes
#   finish                      -> prints summary, exit code = number of failed checks
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lab-lib.sh"

_PASS=0
_FAIL=0
_GUARD_PASS=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  \033[32m[PASS]\033[0m %s\n' "$desc"; _PASS=$((_PASS + 1))
  else
    printf '  \033[31m[FAIL]\033[0m %s\n' "$desc"; _FAIL=$((_FAIL + 1))
  fi
}

check_eq() {
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" == "$expected" ]; then
    printf '  \033[32m[PASS]\033[0m %s\n' "$desc"; _PASS=$((_PASS + 1))
  else
    printf '  \033[31m[FAIL]\033[0m %s  (got: "%s", want: "%s")\n' "$desc" "$actual" "$expected"
    _FAIL=$((_FAIL + 1))
  fi
}

guard() {
  local before=$_PASS; check "$@"; [ $_PASS -eq $before ] || _GUARD_PASS=$((_GUARD_PASS + 1))
}

guard_eq() {
  local before=$_PASS; check_eq "$@"; [ $_PASS -eq $before ] || _GUARD_PASS=$((_GUARD_PASS + 1))
}

# Exec in a pod with a short timeout; for connectivity tests.
pod_exec() { local ns="$1" pod="$2"; shift 2; timeout 15 kubectl -n "$ns" exec "$pod" -- "$@"; }

# kubectl get, errors silenced
kget() { kubectl get "$@" 2>/dev/null; }

finish() {
  local total=$((_PASS + _FAIL))
  echo "  ----"
  if [ "$_PASS" -gt 0 ] && [ "$_PASS" -eq "$_GUARD_PASS" ]; then
    echo "  (only \"don't break\" checks passed: the task is not done, so they score nothing)"
    _PASS=0
  fi
  if [ "$_FAIL" -eq 0 ]; then
    printf '  \033[32mRESULT %d/%d checks passed\033[0m\n' "$_PASS" "$total"
  else
    printf '  \033[31mRESULT %d/%d checks passed\033[0m\n' "$_PASS" "$total"
  fi
  exit "$_FAIL"
}
