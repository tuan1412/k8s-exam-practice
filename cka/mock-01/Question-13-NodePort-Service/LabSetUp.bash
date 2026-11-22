#!/bin/bash
# Q13 — Deployment nodeport-deployment (2 replicas, no container port) in ns relative
set -e
kubectl create ns relative --dry-run=client -oyaml | kubectl apply -f - >/dev/null
kubectl -n relative delete svc nodeport-service --ignore-not-found >/dev/null
kubectl -n relative delete deploy nodeport-deployment --ignore-not-found >/dev/null
kubectl -n relative create deployment nodeport-deployment --image=nginx:1-alpine --replicas=2 >/dev/null
ports() { kubectl get svc -A -ojsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.spec.ports[*].nodePort}{"\n"}{end}'; }
used=$(ports | awk '/ 30080( |$)/ {print $1}')
if [ "$used" == nginx-gateway/nginx-gateway ]; then
  # NGINX Gateway Fabric left by another exam's lab: move it to a free port (its setup moves it back)
  free=$(for p in $(seq 30090 30199); do ports | grep -qw "$p" || { echo $p; break; }; done)
  kubectl -n nginx-gateway patch svc nginx-gateway --type=json \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/ports/0/nodePort\",\"value\":$free}]" >/dev/null
  echo "Moved nginx-gateway (another exam's lab) from NodePort 30080 to $free"
elif [ -n "$used" ]; then
  echo "WARNING: NodePort 30080 is already used by $used — free it first (another exam's lab?)."
fi
echo "Deployment relative/nodeport-deployment created"
