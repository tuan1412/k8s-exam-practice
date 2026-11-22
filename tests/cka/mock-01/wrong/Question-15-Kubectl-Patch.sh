# right values, wrong command
kubectl -n patch-ns set resources deploy resource-app -c nginx --limits=cpu=500m,memory=512Mi
kubectl -n patch-ns rollout status deploy resource-app --timeout=180s
