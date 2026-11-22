#!/usr/bin/env bash
# Set up the lab for one question (or all) and print the task.
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

INCLUDE_DESTRUCTIVE="${INCLUDE_DESTRUCTIVE:-0}"
parse_args "$@"
require_root
require_kubectl

setup_one() {
  local dir="$1" name; name=$(basename "$dir")
  if [ -f "$dir/DESTRUCTIVE" ] && [ "$QUESTION" == "all" ] && [ "$INCLUDE_DESTRUCTIVE" != "1" ]; then
    echo "$(c_bold "== $name") skipped (destructive, run alone: $(basename "$0") ${name})"
    return
  fi
  echo "$(c_bold "== Setup $name")"
  bash "$dir/LabSetUp.bash"
}

if [ "$QUESTION" == "all" ]; then
  for d in $(list_questions); do setup_one "$d"; done
  echo
  echo "$(c_green "All labs ready.") Tasks: cat $MOCK_DIR/*/Questions.bash | less"
  echo "Time limit 120 min. Score with: scripts/validate-question.sh -m $MOCK all"
else
  dir=$(resolve_question "$QUESTION")
  if [ -f "$dir/DESTRUCTIVE" ]; then
    echo "$(c_red "WARNING:") $(cat "$dir/DESTRUCTIVE")"
    read -r -p "Continue? [y/N] " ans; [[ "$ans" =~ ^[yY]$ ]] || exit 0
  fi
  setup_one "$dir"
  echo
  bash "$dir/Questions.bash"
  echo
  echo "Done? scripts/validate-question.sh -m $MOCK $QUESTION"   # no solution path here: the exam UI shows this log while you work
fi
