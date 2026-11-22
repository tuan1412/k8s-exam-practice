#!/bin/bash
# Reinstall the simulator's original CNI (Calico manifest) only when no CNI is running
S=/var/lib/k8s-exam-practice/q19-cni-removed
[ -f $S ] || exit 0
if kubectl get ds -A -oname 2>/dev/null | grep -qE '/(calico-node|kube-flannel-ds|canal|cilium)$'; then
  echo "A CNI is running: leaving it as it is."
else
  CIDR=$(cat $S); [ "$CIDR" != unknown ] || CIDR=10.244.0.0/16
  echo "Reinstalling Calico v3.29.1 (pod CIDR $CIDR)..."
  curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml \
    | sed -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
          -e "s|#   value: \"192.168.0.0/16\"|  value: \"$CIDR\"|" \
    | kubectl apply -f - >/dev/null
  kubectl -n kube-system rollout status ds calico-node --timeout=300s
  kubectl -n kube-system rollout restart deploy coredns
fi
rm -f $S
