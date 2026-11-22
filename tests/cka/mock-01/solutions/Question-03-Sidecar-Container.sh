kubectl -n default patch deploy wordpress --type=strategic -p '{"spec":{"template":{"spec":{
  "volumes":[{"name":"logs","emptyDir":{}}],
  "containers":[
    {"name":"wordpress","volumeMounts":[{"name":"logs","mountPath":"/var/log"}]},
    {"name":"sidecar","image":"busybox:stable","command":["/bin/sh","-c","tail -f /var/log/wordpress.log"],
     "volumeMounts":[{"name":"logs","mountPath":"/var/log"}]}]}}}}'
kubectl -n default rollout status deploy wordpress --timeout=300s
sleep 8
