#!/bin/bash
cat <<'QUESTION'
Q9 · Migrate Ingress to Gateway API

You have an existing web application deployed in the default namespace using an Ingress resource named web. You must migrate the existing Ingress configuration to the new Kubernetes Gateway API, maintaining the existing HTTPS access configuration.

- Create a Gateway resource named web-gateway with hostname gateway.web.k8s.local that maintains the existing TLS and listener configuration from the existing Ingress resource named web
- Create an HTTPRoute resource named web-route with hostname gateway.web.k8s.local that maintains the existing routing rules from the current Ingress resource named web

ℹ️ A GatewayClass named nginx-class is already installed in the cluster

Docs: Gateway API (gateway-api.sigs.k8s.io) · Gateway · HTTPRoute
[Lab] nginx-class points to a controller that does not run here, so the Gateway is never Programmed; only the resources are graded.
QUESTION
