# Q15 — Solution
kubectl -n patch-ns patch deploy resource-app -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","resources":{"limits":{"cpu":"500m","memory":"512Mi"}}}]}}}}'
kubectl -n patch-ns get deploy resource-app -ojsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
kubectl -n patch-ns rollout status deploy resource-app

# The default patch type for built-in objects is "strategic": containers are merged by name, so
# requests and the other fields stay. A JSON patch works too:
#   kubectl -n patch-ns patch deploy resource-app --type=json -p '[
#     {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"500m"},
#     {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"512Mi"}]'
#
# Traps: --type=merge replaces the whole containers LIST (name + resources only -> invalid / image lost);
#        quote the JSON with single quotes; check with: kubectl get deploy -oyaml --show-managed-fields
