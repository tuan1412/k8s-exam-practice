#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
D="-n relative-fawn deploy wordpress"
W=$(cat "$STATE_DIR/q16-node" 2>/dev/null || pick_worker)
c='{.spec.template.spec.containers[0].resources'
req_cpu=$(to_milli "$(kget $D -ojsonpath="${c}.requests.cpu}")"); req_mem=$(to_bytes "$(kget $D -ojsonpath="${c}.requests.memory}")")
check "Requests raised above 100m CPU and 100Mi memory" test "$req_cpu" -gt 100 -a "$req_mem" -gt $((100 << 20))
guard_eq "Limits unchanged (300m, 500Mi)" "$(kget $D -ojsonpath="${c}.limits.cpu} ${c}.limits.memory}")" "300m 500Mi"
# status.replicas counts the Pods of every ReplicaSet: 3 means no old Pod is left over from a
# rollout that could not finish (an old Pod still counts as available)
guard_eq "3 replicas, all updated and available, no old Pod left (spec/total/updated/ready/available)" \
  "$(kget $D -ojsonpath='{.spec.replicas}/{.status.replicas}/{.status.updatedReplicas}/{.status.readyReplicas}/{.status.availableReplicas}')" "3/3/3/3/3"
pending=$(kget -n relative-fawn pod -l app=wordpress --field-selector status.phase=Pending -oname | wc -l)
guard_eq "No wordpress Pod left Pending (requests too big to schedule)" "$pending" "0"

# fair share = (Allocatable - other Pods' requests) / 3, capped by the limit; ask for at least half of it
alloc_cpu=$(to_milli "$(kget node "$W" -ojsonpath='{.status.allocatable.cpu}')")
alloc_mem=$(to_bytes "$(kget node "$W" -ojsonpath='{.status.allocatable.memory}')")
used=$(kubectl describe node "$W" 2>/dev/null | awk '/^Allocated resources/ {s=1} s && $1=="cpu" {c=$2} s && $1=="memory" {print c, $2; exit}')
wp=$(kget -n relative-fawn pod -l app=wordpress --field-selector spec.nodeName="$W",status.phase!=Succeeded,status.phase!=Failed -oname | wc -l)
share_cpu=$(( (alloc_cpu - $(to_milli "${used% *}") + wp * req_cpu) / 3 )); [ $share_cpu -le 300 ] || share_cpu=300
share_mem=$(( (alloc_mem - $(to_bytes "${used#* }") + wp * req_mem) / 3 )); [ $share_mem -le $((500 << 20)) ] || share_mem=$((500 << 20))
guard "CPU request ${req_cpu}m >= half of the fair share (${share_cpu}m)" test $((req_cpu * 2)) -ge $share_cpu
guard "Memory request $((req_mem >> 20))Mi >= half of the fair share ($((share_mem >> 20))Mi)" test $((req_mem / 1024 * 2)) -ge $((share_mem / 1024))
finish
