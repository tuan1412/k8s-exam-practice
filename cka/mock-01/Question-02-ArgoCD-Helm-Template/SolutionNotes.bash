# Q2 — Solution
helm repo add argocd https://argoproj.github.io/argo-helm
helm repo update
kubectl create namespace argocd

helm search repo argocd/argo-cd --versions | grep 7.7.3
helm show values argocd/argo-cd --version 7.7.3 | grep -i -A3 '^crds:'    # crds.install: true

helm template argocd argocd/argo-cd --version 7.7.3 --namespace argocd \
  --set crds.install=false > /root/argo-helm.yaml

grep -c 'kind: CustomResourceDefinition' /root/argo-helm.yaml    # 0

# Traps: --skip-crds only skips the chart's crds/ folder; argo-cd renders its CRDs from templates/
#        behind the value crds.install, so --skip-crds alone still writes the CRDs into the file.
#        Don't forget --version 7.7.3 and --namespace argocd.
