# Flannel: pods talk to each other, but NetworkPolicies are not enforced
kubectl apply -f https://github.com/flannel-io/flannel/releases/download/v0.26.1/kube-flannel.yml
kubectl -n kube-flannel rollout status ds kube-flannel-ds --timeout=300s
