#!/bin/bash
cat <<'QUESTION'
Q13 · NodePort Service

There is a Deployment named nodeport-deployment in the relative namespace.

- Configure the Deployment so it can be exposed on port 80, name http, protocol TCP
- Create a new Service named nodeport-service exposing the container port 80, protocol TCP, NodePort 30080
- Configure the new Service to also expose the individual Pods using NodePort

Docs: Service (type NodePort) · Connecting Applications with Services
QUESTION
