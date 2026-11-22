#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
F=/root/argo-helm.yaml
check_eq "Helm repo argocd -> https://argoproj.github.io/argo-helm" \
  "$(helm repo list 2>/dev/null | awk '$1=="argocd" {print $2}' | sed 's|/$||')" "https://argoproj.github.io/argo-helm"
check "Namespace argocd exists" kubectl get ns argocd
check "$F rendered from chart argo-cd 7.7.3" grep -q 'helm.sh/chart: argo-cd-7.7.3' $F
check "$F targets namespace argocd" grep -qE '^\s+namespace: "?argocd"?\s*$' $F
check "$F contains the Argo CD components (argocd-server Deployment)" grep -q 'name: argocd-server$' $F
check "$F contains no CustomResourceDefinition" bash -c "[ -s $F ] && ! grep -q 'kind: CustomResourceDefinition' $F"
finish
