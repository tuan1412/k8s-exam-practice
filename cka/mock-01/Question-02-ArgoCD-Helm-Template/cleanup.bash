#!/bin/bash
helm -n argocd uninstall argocd >/dev/null 2>&1 || true
kubectl delete ns argocd --ignore-not-found
helm repo remove argocd >/dev/null 2>&1 || true
rm -f /root/argo-helm.yaml
