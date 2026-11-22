# sidecar without the shared volume: tails a file that does not exist in its own filesystem
kubectl -n default patch deploy wordpress --type=strategic -p '{"spec":{"template":{"spec":{
  "containers":[{"name":"sidecar","image":"busybox:stable","command":["/bin/sh","-c","tail -f /var/log/wordpress.log"]}]}}}}'
kubectl -n default rollout status deploy wordpress --timeout=60s || true
sleep 8
