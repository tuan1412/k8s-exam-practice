kubectl create priorityclass high-priority --value=999 --description="high priority"
kubectl -n priority patch deploy busybox-logger -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
kubectl -n priority rollout status deploy busybox-logger --timeout=180s
