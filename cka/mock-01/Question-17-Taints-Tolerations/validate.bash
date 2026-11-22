#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
W=$(cat "$STATE_DIR/q17-node" 2>/dev/null || pick_worker)
check_eq "Node $W has taint PERMISSION=granted:NoSchedule" \
  "$(kget node "$W" -ojsonpath='{.spec.taints[?(@.key=="PERMISSION")].value}:{.spec.taints[?(@.key=="PERMISSION")].effect}')" "granted:NoSchedule"
tol=$(kget -n default pod nginx -ojsonpath='{range .spec.tolerations[?(@.key=="PERMISSION")]}{.operator}/{.value}/{.effect}{"\n"}{end}')
check "Pod nginx tolerates PERMISSION=granted:NoSchedule" \
  bash -c 'grep -qxE "(Equal|)/granted/(NoSchedule|)|Exists//(NoSchedule|)" <<< "$1"' _ "$tol"
check "Pod nginx uses image nginx" \
  bash -c '[[ "$1" =~ ^(docker\.io/(library/)?)?nginx(:[^/]+)?$ ]]' _ "$(kget -n default pod nginx -ojsonpath='{.spec.containers[0].image}')"
check_eq "Pod nginx Running on $W" "$(kget -n default pod nginx -ojsonpath='{.status.phase}/{.spec.nodeName}')" "Running/$W"
finish
