sed -i -E '/--etcd-servers=/ s/:2380/:2379/g' /etc/kubernetes/manifests/kube-apiserver.yaml
sleep 20
for _ in $(seq 60); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 5; done
kubectl -n kube-system wait --for=condition=Ready pod -l component=kube-apiserver --timeout=120s
