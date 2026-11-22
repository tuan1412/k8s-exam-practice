#!/bin/bash
# Q4 — Deployment wordpress (ns wordpress), 3 replicas pinned to one worker, init container, no resources
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
W=$(pick_worker)
mkdir -p "$STATE_DIR" && echo "$W" > "$STATE_DIR/q4-node"
kubectl create ns wordpress --dry-run=client -oyaml | kubectl apply -f - >/dev/null
cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: wordpress
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
      initContainers:
      - name: init-setup
        image: busybox:stable
        command: ["sh", "-c", "echo 'Preparing environment...' && sleep 5"]
      containers:
      - name: wordpress
        image: wordpress:php8.2-apache
        ports:
        - containerPort: 80
YAML
echo "Deployment wordpress/wordpress: 3 replicas on node $W"
