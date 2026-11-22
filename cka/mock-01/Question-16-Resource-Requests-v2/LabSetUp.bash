#!/bin/bash
# Q16 — Deployment wordpress (ns relative-fawn), 3 replicas on one worker with undersized requests
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
W=$(pick_worker)
mkdir -p "$STATE_DIR" && echo "$W" > "$STATE_DIR/q16-node"
kubectl create ns relative-fawn --dry-run=client -oyaml | kubectl apply -f - >/dev/null
kubectl -n relative-fawn delete deploy wordpress --ignore-not-found >/dev/null
cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: relative-fawn
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      nodeSelector:
        kubernetes.io/hostname: $W
      containers:
      - name: wordpress
        image: wordpress:php8.2-apache
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
          limits:
            cpu: 300m
            memory: 500Mi
YAML
echo "Deployment relative-fawn/wordpress: 3 replicas on node $W"
