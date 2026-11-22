#!/bin/bash
# Q14 — nginx serving HTTPS with TLSv1.2+1.3 from a ConfigMap, Service nginx-static (ClusterIP :443)
set -e
sed -i '/ckaquestion\.k8s\.local/d' /etc/hosts
kubectl create ns nginx-static --dry-run=client -oyaml | kubectl apply -f - >/dev/null
if ! kubectl -n nginx-static get secret nginx-tls >/dev/null 2>&1; then
  T=$(mktemp -d)
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $T/tls.key -out $T/tls.crt \
    -subj "/CN=ckaquestion.k8s.local" >/dev/null 2>&1
  kubectl -n nginx-static create secret tls nginx-tls --cert=$T/tls.crt --key=$T/tls.key >/dev/null
  rm -rf $T
fi
cat <<'YAML' | kubectl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: nginx-static
data:
  nginx.conf: |
    events {}
    http {
      server {
        listen 443 ssl;
        ssl_certificate /etc/nginx/tls/tls.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        location / {
          return 200 "Hello TLS\n";
        }
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-static
  namespace: nginx-static
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-static
  template:
    metadata:
      labels:
        app: nginx-static
    spec:
      containers:
      - name: nginx
        image: nginx:1-alpine
        ports:
        - containerPort: 443
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: tls
          mountPath: /etc/nginx/tls
      volumes:
      - name: config
        configMap:
          name: nginx-config
      - name: tls
        secret:
          secretName: nginx-tls
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-static
  namespace: nginx-static
spec:
  selector:
    app: nginx-static
  ports:
  - port: 443
    targetPort: 443
YAML
echo "nginx-static serves https on Service nginx-static:443 (TLSv1.2 + TLSv1.3)"
