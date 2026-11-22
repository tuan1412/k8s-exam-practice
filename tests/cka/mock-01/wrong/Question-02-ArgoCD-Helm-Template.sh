# --skip-crds does not skip argo-cd's templated CRDs
helm repo add argocd https://argoproj.github.io/argo-helm
helm repo update argocd
kubectl create ns argocd
helm template argocd argocd/argo-cd --version 7.7.3 --namespace argocd --skip-crds > /root/argo-helm.yaml
