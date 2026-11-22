kubectl -n patch-ns patch deploy resource-app -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","resources":{"limits":{"cpu":"500m","memory":"512Mi"}}}]}}}}'
kubectl -n patch-ns rollout status deploy resource-app --timeout=180s
