#!/bin/bash
# Q7 — user-defined PriorityClasses + Deployment busybox-logger in ns priority
set -e
kubectl delete priorityclass high-priority --ignore-not-found >/dev/null
kubectl create ns priority --dry-run=client -oyaml | kubectl apply -f - >/dev/null
cat <<'YAML' | kubectl apply -f - >/dev/null
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: user-critical
value: 1000
globalDefault: false
description: "Highest user-defined priority class"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: user-batch
value: 400
globalDefault: false
description: "Batch jobs"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: busybox-logger
  namespace: priority
spec:
  replicas: 1
  selector:
    matchLabels:
      app: busybox-logger
  template:
    metadata:
      labels:
        app: busybox-logger
    spec:
      terminationGracePeriodSeconds: 3   # sh as PID 1 ignores SIGTERM: no 30s wait per rollout
      containers:
      - name: busybox
        image: busybox:stable
        command: ["sh", "-c", "while true; do echo 'logging...'; sleep 5; done"]
YAML
echo "PriorityClasses user-critical/user-batch and Deployment priority/busybox-logger created"
