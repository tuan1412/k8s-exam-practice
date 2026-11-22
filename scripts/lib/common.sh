#!/usr/bin/env bash
# Shared helpers for run/validate/cleanup. Sourced, not executed.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_MOCK="${MOCK:-cka/mock-01}"

c_red()   { printf '\033[31m%s\033[0m' "$*"; }
c_green() { printf '\033[32m%s\033[0m' "$*"; }
c_bold()  { printf '\033[1m%s\033[0m' "$*"; }

die() { echo "$(c_red ERROR:) $*" >&2; exit 1; }

usage_common() {
  cat <<USAGE
Usage: $(basename "$0") [-m <exam/mock>] <question>

  <question>  number (1, 01), folder name (Question-05-...) or 'all'
  -m          question set, default: ${DEFAULT_MOCK}   (see: ls cka/)

Examples:
  $(basename "$0") 5
  $(basename "$0") Question-13-Gateway-API-HTTPRoute
  $(basename "$0") -m cka/mock-01 all
USAGE
}

# parse_args "$@" -> sets MOCK_DIR and QUESTION
parse_args() {
  local mock="$DEFAULT_MOCK"
  while getopts ":m:h" opt; do
    case $opt in
      m) mock="$OPTARG" ;;
      h) usage_common; exit 0 ;;
      *) usage_common; exit 1 ;;
    esac
  done
  shift $((OPTIND - 1))
  [ $# -ge 1 ] || { usage_common; exit 1; }
  MOCK="$mock"
  MOCK_DIR="$REPO_ROOT/$mock"
  [ -d "$MOCK_DIR" ] || die "question set not found: $mock"
  QUESTION="$1"
}

# resolve_question <id> -> prints the question folder path
resolve_question() {
  local id="$1" d
  if [ -d "$MOCK_DIR/$id" ]; then echo "$MOCK_DIR/$id"; return; fi
  case "$id" in
    [0-9]*)     d=$(ls -d "$MOCK_DIR"/Question-"$(printf '%02d' "$((10#$id))")"-* 2>/dev/null | head -1) ;;
  esac
  [ -n "${d:-}" ] && [ -d "$d" ] || die "question '$id' not found in $MOCK_DIR"
  echo "$d"
}

# list_questions -> all question folders, in order
list_questions() {
  ls -d "$MOCK_DIR"/Question-* 2>/dev/null
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "run as root (sudo -i): scripts write /opt/exam and read /etc/kubernetes"
}

require_kubectl() {
  command -v kubectl >/dev/null || die "kubectl not found"
  kubectl get --raw /readyz >/dev/null 2>&1 || die "kubectl cannot reach the cluster"
}

# For grading/cleanup: a broken apiserver can be the task itself (e.g. mock-01 Q15), so keep going
warn_kubectl() {
  command -v kubectl >/dev/null || die "kubectl not found"
  kubectl get --raw /readyz >/dev/null 2>&1 \
    || echo "$(c_red WARNING:) kubectl cannot reach the cluster: cluster checks will fail" >&2
}
