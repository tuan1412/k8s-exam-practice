#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
D="-n wordpress deploy wordpress"
W=$(cat "$STATE_DIR/q4-node" 2>/dev/null || pick_worker)
res() { kget $D -ojsonpath="{.spec.template.spec.$1[0].resources.$2}"; }
guard_eq "Deployment scaled back to 3 replicas, 3 available, no old Pod left (spec/total/available/updated)" \
  "$(kget $D -ojsonpath='{.spec.replicas}/{.status.replicas}/{.status.availableReplicas}/{.status.updatedReplicas}')" "3/3/3/3"
check "Main container has cpu+memory requests and limits" \
  bash -c '[ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ]' _ \
  "$(res containers requests.cpu)" "$(res containers requests.memory)" "$(res containers limits.cpu)" "$(res containers limits.memory)"
init="$(res initContainers requests.cpu) $(res initContainers requests.memory) $(res initContainers limits.cpu) $(res initContainers limits.memory)"
main="$(res containers requests.cpu) $(res containers requests.memory) $(res containers limits.cpu) $(res containers limits.memory)"
check "Init container has exactly the same requests/limits as the main container (init: $init / main: $main)" \
  bash -c '[ -n "$(echo $2)" ] && [ "$1" == "$2" ]' _ "$init" "$main"

# The 3 Pods must share what is left on the node: together at least 40% of it (scheduling caps the top)
req_cpu=$(to_milli "$(res containers requests.cpu)"); req_mem=$(to_bytes "$(res containers requests.memory)")
alloc_cpu=$(to_milli "$(kget node "$W" -ojsonpath='{.status.allocatable.cpu}')")
alloc_mem=$(to_bytes "$(kget node "$W" -ojsonpath='{.status.allocatable.memory}')")
used=$(kubectl describe node "$W" 2>/dev/null | awk '/^Allocated resources/ {s=1} s && $1=="cpu" {c=$2} s && $1=="memory" {print c, $2; exit}')
wp=$(kget -n wordpress pod -l app=wordpress --field-selector spec.nodeName="$W",status.phase!=Succeeded,status.phase!=Failed -oname | wc -l)
other_cpu=$(( $(to_milli "${used% *}") - wp * req_cpu )); other_mem=$(( $(to_bytes "${used#* }") - wp * req_mem ))
check "3 x CPU request uses >= 40% of the node's free CPU (got $((3 * req_cpu))m of $((alloc_cpu - other_cpu))m)" \
  test $((3 * req_cpu * 10)) -ge $(( (alloc_cpu - other_cpu) * 4 ))
check "3 x memory request uses >= 40% of the node's free memory (got $((3 * req_mem >> 20))Mi of $(((alloc_mem - other_mem) >> 20))Mi)" \
  test $((3 * req_mem / 1024 * 10)) -ge $(( (alloc_mem - other_mem) / 1024 * 4 ))
finish
