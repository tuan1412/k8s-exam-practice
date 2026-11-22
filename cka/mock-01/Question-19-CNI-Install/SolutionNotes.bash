# Q19 — Solution: only Calico enforces NetworkPolicy (Flannel does not)
kubectl get nodes                                    # NotReady: no CNI
kubectl -n kube-system get cm kubeadm-config -oyaml | grep podSubnet     # e.g. 10.244.0.0/16

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml
wget https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/custom-resources.yaml
vim custom-resources.yaml        # spec.calicoNetwork.ipPools[0].cidr: 192.168.0.0/16 -> the podSubnet above
kubectl create -f custom-resources.yaml

kubectl get tigerastatus                             # calico Available=True (takes 1-3 min)
kubectl -n calico-system get pod
kubectl get nodes                                    # Ready
kubectl -n kube-system rollout restart deploy coredns
kubectl run tmp --image=busybox:stable --rm -it --restart=Never -- nslookup kubernetes.default

# Traps: Flannel looks simpler but has no NetworkPolicy support;
#        the default CIDR in custom-resources.yaml (192.168.0.0/16) must match the cluster's podSubnet;
#        use "kubectl create" for tigera-operator.yaml (apply hits the annotation size limit on its big CRDs).
