#!/bin/bash
# Q9 — Gateway API CRDs, GatewayClass nginx-class, app web-deployment/web-service, TLS secret, Ingress web
set -e
GWAPI=v1.2.1
if ! kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  echo "Installing Gateway API CRDs $GWAPI..."
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/$GWAPI/standard-install.yaml >/dev/null
  kubectl wait --for=condition=Established crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=60s >/dev/null
fi
kubectl -n default delete httproute web-route --ignore-not-found >/dev/null
kubectl -n default delete gateway web-gateway --ignore-not-found >/dev/null
if ! kubectl -n default get secret web-tls >/dev/null 2>&1; then
  T=$(mktemp -d)
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $T/tls.key -out $T/tls.crt \
    -subj "/CN=gateway.web.k8s.local/O=web" >/dev/null 2>&1
  kubectl -n default create secret tls web-tls --cert=$T/tls.crt --key=$T/tls.key >/dev/null
  rm -rf $T
fi
cat <<'YAML' | kubectl apply -f - >/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-deployment
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:1-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-service
  namespace: default
spec:
  selector:
    app: web
  ports:
  - name: http
    port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  namespace: default
spec:
  tls:
  - hosts:
    - gateway.web.k8s.local
    secretName: web-tls
  rules:
  - host: gateway.web.k8s.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx-class
spec:
  controllerName: example.net/nginx-gateway-controller
YAML
echo "Ingress web, Service web-service and GatewayClass nginx-class ready"
