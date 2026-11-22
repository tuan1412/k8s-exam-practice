#!/bin/bash
# Q5 — metrics-server, Deployment + Service apache-deployment in ns autoscale (needs internet)
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
ensure_metrics_server
kubectl create ns autoscale --dry-run=client -oyaml | kubectl apply -f - >/dev/null
kubectl -n autoscale delete hpa apache-server --ignore-not-found >/dev/null
cat <<'YAML' | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apache-deployment
  namespace: autoscale
spec:
  replicas: 1
  selector:
    matchLabels:
      app: apache
  template:
    metadata:
      labels:
        app: apache
    spec:
      containers:
      - name: apache
        image: httpd:2-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
          limits:
            cpu: 200m
---
apiVersion: v1
kind: Service
metadata:
  name: apache-deployment
  namespace: autoscale
spec:
  selector:
    app: apache
  ports:
  - port: 80
    targetPort: 80
YAML
echo "Deployment autoscale/apache-deployment ready for an HPA"
