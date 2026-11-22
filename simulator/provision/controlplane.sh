#!/usr/bin/env bash
# Runs as root on controlplane after k8s-node.sh: kubeadm init, Calico, local-path.
# Env: NODE_IP
set -euo pipefail
: "${NODE_IP:?}"
CALICO=v3.29.1
LOCAL_PATH=v0.0.30
POD_CIDR=10.244.0.0/16   # not 192.168.0.0/16: multipass on macOS uses 192.168.64.0/24

if [ ! -f /etc/kubernetes/admin.conf ]; then
  kubeadm init --apiserver-advertise-address="$NODE_IP" --pod-network-cidr="$POD_CIDR" \
    --node-name controlplane
fi
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf

# Calico enforces NetworkPolicy (Q15)
curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO}/manifests/calico.yaml" \
  | sed -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
        -e "s|#   value: \"192.168.0.0/16\"|  value: \"${POD_CIDR}\"|" \
  | kubectl apply -f - >/dev/null

# Default StorageClass, like most playgrounds (the trap in Q6)
kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LOCAL_PATH}/deploy/local-path-storage.yaml" >/dev/null
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null

kubeadm token create --print-join-command > /root/join.sh
echo "controlplane: done"
