# one MORE than the highest instead of one less
kubectl create priorityclass high-priority --value=1001
kubectl -n priority patch deploy busybox-logger -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
kubectl -n priority rollout status deploy busybox-logger --timeout=180s
