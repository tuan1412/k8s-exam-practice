#!/usr/bin/env bash
# Score one question, or 'all' for the whole set (points from scoring.tsv).
set -uo pipefail
source "$(dirname "$0")/lib/common.sh"

parse_args "$@"
warn_kubectl

validate_one() {
  local dir="$1"
  echo "$(c_bold "== $(basename "$dir")")"
  bash "$dir/validate.bash"
}

if [ "$QUESTION" != "all" ]; then
  validate_one "$(resolve_question "$QUESTION")"
  exit $?
fi

SCORING="$MOCK_DIR/scoring.tsv"
total_score=0; total_max=0; report=""
for d in $(list_questions); do
  name=$(basename "$d")
  out=$(validate_one "$d" 2>&1); echo "$out"
  res=$(echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -oE 'RESULT [0-9]+/[0-9]+' | tail -1 | grep -oE '[0-9]+/[0-9]+')
  passed=${res%/*}; checks=${res#*/}
  pts=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$SCORING" 2>/dev/null); pts=${pts:-0}
  if [ -n "$res" ] && [ "$checks" -gt 0 ]; then
    got=$(awk -v p="$passed" -v c="$checks" -v w="$pts" 'BEGIN{printf "%.1f", w*p/c}')
  else
    got=0; res="error"
  fi
  total_score=$(awk -v a="$total_score" -v b="$got" 'BEGIN{printf "%.1f", a+b}')
  total_max=$((total_max + pts))
  report+=$(printf '%-45s %8s %6s/%s' "$name" "$res" "$got" "$pts")$'\n'
done

echo
echo "$(c_bold "== SCORE $(basename "$MOCK_DIR")")"
printf '%-45s %8s %9s\n' "Question" "checks" "points"
printf '%s' "$report"
echo "-----------------------------------------------------------------"
printf '%-45s %18s\n' "TOTAL" "$total_score/$total_max"
awk -v s="$total_score" 'BEGIN{ if (s>=66) print "\033[32mPASS (real exam: 66%)\033[0m"; else print "\033[31mFAIL (need >= 66)\033[0m" }'
