#!/bin/bash
# Q10 — Deployment echo (HTTP echo server on 8080) in ns echo-sound
set -e
kubectl create ns echo-sound --dry-run=client -oyaml | kubectl apply -f - >/dev/null
kubectl -n echo-sound delete ingress echo --ignore-not-found >/dev/null
kubectl -n echo-sound delete svc echo-service --ignore-not-found >/dev/null
cat <<'YAML' | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo
  namespace: echo-sound
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo
  template:
    metadata:
      labels:
        app: echo
    spec:
      containers:
      - name: echo
        image: registry.k8s.io/e2e-test-images/agnhost:2.39
        args: ["netexec", "--http-port=8080"]
        ports:
        - containerPort: 8080
YAML
echo "Deployment echo-sound/echo listens on 8080 (try /echo?msg=hello)"
