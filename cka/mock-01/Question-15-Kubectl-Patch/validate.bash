#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
D="-n patch-ns deploy resource-app"
c='{.spec.template.spec.containers[?(@.name=="nginx")].resources'
check_eq "nginx limits: cpu 500m, memory 512Mi" "$(kget $D -ojsonpath="${c}.limits.cpu} ${c}.limits.memory}")" "500m 512Mi"
# kubectl patch records itself as field manager "kubectl-patch" (edit: kubectl-edit, set: kubectl-set, apply: kubectl-client-side-apply)
owner=$(kubectl get $D --show-managed-fields -ojson 2>/dev/null | jq -r '.metadata.managedFields[]
  | select(.fieldsV1 | tostring | test("f:limits\":\\{(\".\":\\{\\},)?\"f:cpu\"")) | .manager' 2>/dev/null | xargs)
check_eq "The limits were changed with kubectl patch (field manager)" "$owner" "kubectl-patch"
guard_eq "Requests unchanged (100m, 128Mi)" "$(kget $D -ojsonpath="${c}.requests.cpu} ${c}.requests.memory}")" "100m 128Mi"
guard_eq "Still 2 replicas, all updated and available" \
  "$(kget $D -ojsonpath='{.spec.replicas}/{.status.updatedReplicas}/{.status.availableReplicas}')" "2/2/2"
finish
