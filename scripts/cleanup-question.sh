#!/usr/bin/env bash
# Remove a question's resources (or all) so it can be redone.
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

parse_args "$@"
require_root
warn_kubectl

cleanup_one() {
  local dir="$1"
  echo "$(c_bold "== Cleanup $(basename "$dir")")"
  bash "$dir/cleanup.bash" || true
}

if [ "$QUESTION" == "all" ]; then
  for d in $(list_questions); do cleanup_one "$d"; done
else
  cleanup_one "$(resolve_question "$QUESTION")"
fi
