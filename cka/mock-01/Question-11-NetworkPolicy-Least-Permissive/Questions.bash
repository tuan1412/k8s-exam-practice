#!/bin/bash
cat <<'QUESTION'
Q11 · NetworkPolicy

There are two Deployments, frontend-deployment and backend-deployment. The frontend runs in the frontend namespace, the backend in the backend namespace (exposed by Service backend-service).

- Look at the NetworkPolicy YAML files in /root/network-policies
- Decide which of the policies provides the functionality to allow interaction between the frontend and the backend Deployments in the least permissive way, and deploy that YAML

Do not create, modify or deploy any other NetworkPolicy.

Docs: Network Policies
QUESTION
