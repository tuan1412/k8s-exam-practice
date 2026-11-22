#!/bin/bash
# Q3 — Deployment wordpress (default ns) whose container writes /var/log/wordpress.log
set -e
cat <<'YAML' | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: default
  labels:
    app: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      terminationGracePeriodSeconds: 3   # sh as PID 1 ignores SIGTERM: no 30s wait per rollout
      containers:
      - name: wordpress
        image: wordpress:php8.2-apache
        command: ["/bin/sh", "-c", "while true; do echo 'WordPress is running...' >> /var/log/wordpress.log; sleep 5; done"]
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  namespace: default
spec:
  selector:
    app: wordpress
  ports:
  - port: 80
    targetPort: 80
YAML
