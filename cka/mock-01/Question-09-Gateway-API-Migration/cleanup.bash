#!/bin/bash
kubectl -n default delete httproute web-route --ignore-not-found
kubectl -n default delete gateway web-gateway --ignore-not-found
kubectl delete gatewayclass nginx-class --ignore-not-found
kubectl -n default delete ingress web --ignore-not-found
kubectl -n default delete secret web-tls --ignore-not-found
kubectl -n default delete svc web-service --ignore-not-found
kubectl -n default delete deploy web-deployment --ignore-not-found
# Gateway API CRDs stay: they are cluster-wide and shared with other labs
