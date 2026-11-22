#!/bin/bash
# Q2 — helm available, no argocd repo/namespace/manifest yet (needs internet)
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
ensure_helm
helm repo remove argocd >/dev/null 2>&1 || true
rm -f /root/argo-helm.yaml
echo "helm $(helm version --short) ready"
