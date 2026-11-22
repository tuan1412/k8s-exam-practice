#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
H="-n autoscale hpa apache-server"
check_eq "HPA apache-server targets Deployment apache-deployment" \
  "$(kget $H -ojsonpath='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}')" "Deployment/apache-deployment"
check_eq "Target 50% CPU utilization" \
  "$(kget $H -ojsonpath='{.spec.metrics[?(@.resource.name=="cpu")].resource.target.type}:{.spec.metrics[?(@.resource.name=="cpu")].resource.target.averageUtilization}')" "Utilization:50"
check_eq "minReplicas 1, maxReplicas 4" "$(kget $H -ojsonpath='{.spec.minReplicas}-{.spec.maxReplicas}')" "1-4"
check_eq "Downscale stabilization window 30s" \
  "$(kget $H -ojsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}')" "30"
guard "Deployment apache-deployment still exists" kubectl -n autoscale get deploy apache-deployment
finish
