#!/bin/bash
cat <<'QUESTION'
Q14 · TLS Configuration

There is an existing Deployment in the nginx-static namespace. The Deployment uses a ConfigMap that supports TLSv1.2 and TLSv1.3, as well as a Secret for TLS. There is a Service called nginx-static in the nginx-static namespace that is currently exposing the Deployment.

- Configure the ConfigMap to only support TLSv1.3
- Add the IP address of the Service to /etc/hosts and name it ckaquestion.k8s.local
- Verify everything is working using the following commands:

curl -vk --tls-max 1.2 https://ckaquestion.k8s.local   # should fail
curl -vk --tlsv1.3 https://ckaquestion.k8s.local       # should work

Docs: ConfigMaps · Configure a Pod to Use a ConfigMap
QUESTION
