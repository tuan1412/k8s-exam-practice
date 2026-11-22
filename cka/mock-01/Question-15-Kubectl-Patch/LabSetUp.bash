#!/bin/bash
# Q15 — Deployment resource-app (2 replicas) whose limits are too low
set -e
kubectl create ns patch-ns --dry-run=client -oyaml | kubectl apply -f - >/dev/null
kubectl -n patch-ns delete deploy resource-app --ignore-not-found >/dev/null
cat <<'YAML' | kubectl create -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-app
  namespace: patch-ns
spec:
  replicas: 2
  selector:
    matchLabels:
      app: resource-app
  template:
    metadata:
      labels:
        app: resource-app
    spec:
      containers:
      - name: nginx
        image: nginx:1-alpine
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
YAML
echo "Deployment patch-ns/resource-app created"
