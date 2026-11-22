# resources only on the main container, the init container is forgotten
kubectl -n wordpress scale deploy wordpress --replicas 0
kubectl -n wordpress patch deploy wordpress --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/resources",
  "value":{"requests":{"cpu":"300m","memory":"300Mi"},"limits":{"cpu":"300m","memory":"300Mi"}}}]'
kubectl -n wordpress scale deploy wordpress --replicas 3
kubectl -n wordpress rollout status deploy wordpress --timeout=300s
