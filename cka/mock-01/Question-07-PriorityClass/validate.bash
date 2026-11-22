#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
# highest user-defined class: everything below the system range (1e9), except the new one
max=$(kubectl get priorityclass -o jsonpath='{range .items[*]}{.metadata.name} {.value}{"\n"}{end}' 2>/dev/null \
  | awk '$1 != "high-priority" && $2 <= 1000000000 && $2 > m {m = $2} END {print m + 0}')
check_eq "PriorityClass high-priority value = highest user-defined - 1" \
  "$(kget priorityclass high-priority -ojsonpath='{.value}')" "$((max - 1))"
guard "high-priority is not globalDefault" \
  bash -c '[ -n "$1" ] && [ "$2" != true ]' _ "$(kget priorityclass high-priority -oname)" "$(kget priorityclass high-priority -ojsonpath='{.globalDefault}')"
check_eq "Deployment busybox-logger uses priorityClassName high-priority" \
  "$(kget -n priority deploy busybox-logger -ojsonpath='{.spec.template.spec.priorityClassName}')" "high-priority"
check "A running busybox-logger Pod has priority $((max - 1))" \
  bash -c "kubectl -n priority get pod -l app=busybox-logger --field-selector status.phase=Running \
    -ojsonpath='{range .items[*]}{.spec.priority}{\"\\n\"}{end}' | grep -qx '$((max - 1))'"
finish
