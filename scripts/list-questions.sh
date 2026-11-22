#!/usr/bin/env bash
# List the questions of a set with points.
source "$(dirname "$0")/lib/common.sh"
MOCK_DIR="$REPO_ROOT/${1:-$DEFAULT_MOCK}"
[ -d "$MOCK_DIR" ] || die "question set not found: ${1:-$DEFAULT_MOCK}"
printf '%-45s %6s  %s\n' "Question" "points" "domain"
for d in $(list_questions); do
  n=$(basename "$d")
  line=$(awk -F'\t' -v n="$n" '$1==n {print $2"\t"$3}' "$MOCK_DIR/scoring.tsv")
  flag=""; [ -f "$d/DESTRUCTIVE" ] && flag=" ⚠ destructive"
  printf '%-45s %6s  %s%s\n' "$n" "${line%%$'\t'*}" "${line#*$'\t'}" "$flag"
done
