# Q9 — Solution
kubectl describe ingress web          # host gateway.web.k8s.local, TLS secret web-tls, / -> web-service:80

cat <<'YAML' | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gateway
  namespace: default
spec:
  gatewayClassName: nginx-class
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: gateway.web.k8s.local
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: web-tls
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: web-route
  namespace: default
spec:
  parentRefs:
  - name: web-gateway
  hostnames:
  - gateway.web.k8s.local
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: web-service
      port: 80
YAML
kubectl get gateway,httproute

# Traps: the Ingress terminates TLS -> listener protocol HTTPS on 443 with tls.certificateRefs,
#        not an HTTP listener on 80; HTTPRoute attaches via parentRefs, Ingress "Prefix /" = PathPrefix /.
