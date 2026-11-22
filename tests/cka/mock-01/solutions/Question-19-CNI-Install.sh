# DESTRUCTIVE lab: only with INCLUDE_DESTRUCTIVE=1 on a throwaway cluster
CIDR=$(cat /var/lib/k8s-exam-practice/q19-cni-removed)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml
kubectl -n tigera-operator rollout status deploy tigera-operator --timeout=180s
kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=120s
curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/custom-resources.yaml \
  | sed "s|cidr: 192.168.0.0/16|cidr: $CIDR|" | kubectl create -f -
for _ in $(seq 60); do kubectl -n calico-system get ds calico-node >/dev/null 2>&1 && break; sleep 5; done
kubectl -n calico-system rollout status ds calico-node --timeout=600s
kubectl wait --for=condition=Ready node --all --timeout=300s
kubectl -n kube-system rollout restart deploy coredns
kubectl -n kube-system rollout status deploy coredns --timeout=300s
