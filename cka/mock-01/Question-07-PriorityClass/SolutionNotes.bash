# Q7 — Solution
kubectl get priorityclass          # ignore system-* (2000000000+): highest user-defined = user-critical 1000
kubectl create priorityclass high-priority --value=999 --description="high priority for user workloads"
kubectl -n priority patch deploy busybox-logger \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
kubectl -n priority rollout status deploy busybox-logger
kubectl -n priority get pod -o custom-columns=NAME:.metadata.name,PC:.spec.priorityClassName,PRIO:.spec.priority

# Traps: system-cluster-critical / system-node-critical are not user-defined;
#        "one less" = 999, not 1001; don't set globalDefault;
#        priorityClassName belongs to the Pod template (spec.template.spec), not to the Deployment spec.
