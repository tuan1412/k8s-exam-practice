#!/bin/bash
# Q19 — DESTRUCTIVE: remove the cluster's CNI (Calico manifest/operator, Canal, Cilium, Flannel) from all nodes
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
CIDR=$(kubectl -n kube-system get cm kubeadm-config -ojsonpath='{.data.ClusterConfiguration}' | awk '/podSubnet:/ {print $2}')
mkdir -p "$STATE_DIR" && echo "${CIDR:-unknown}" > "$STATE_DIR/q19-cni-removed"

echo "Removing the CNI from the cluster..."
if kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; then
  kubectl delete installation default --ignore-not-found --timeout=120s || true
fi
kubectl delete ns tigera-operator calico-system calico-apiserver kube-flannel cilium --ignore-not-found --timeout=180s || true
kubectl -n kube-system delete ds calico-node canal kube-flannel-ds cilium cilium-envoy --ignore-not-found
kubectl -n kube-system delete deploy calico-kube-controllers cilium-operator --ignore-not-found
kubectl -n kube-system delete cm calico-config canal-config cilium-config --ignore-not-found
crds=$(kubectl get crd -oname | grep -E 'projectcalico\.org|tigera\.io|cilium\.io' || true)
[ -z "$crds" ] || kubectl delete $crds --timeout=120s || true
for kind in clusterrolebinding clusterrole; do
  objs=$(kubectl get $kind -oname | grep -E '/(calico|canal|flannel|cilium|tigera)' || true)
  [ -z "$objs" ] || kubectl delete $objs --ignore-not-found
done

NODE_CLEAN='rm -f /etc/cni/net.d/*calico* /etc/cni/net.d/*canal* /etc/cni/net.d/*cilium* /etc/cni/net.d/*flannel*
for l in vxlan.calico cilium_vxlan cilium_host cilium_net flannel.1 cni0; do ip link delete $l 2>/dev/null || true; done
ip route flush proto bird 2>/dev/null || true'
for n in $(kubectl get nodes -ojsonpath='{.items[*].metadata.name}'); do
  if [ "$n" == "$(hostname)" ]; then bash -c "$NODE_CLEAN"
  else ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$n" "$NODE_CLEAN" || echo "WARNING: could not clean node $n over ssh"
  fi
done

# DNS Pods now need a CNI to start again
kubectl -n kube-system rollout restart deploy coredns >/dev/null
# kubelet notices the missing CNI config only at its next status sync: wait for it, so the
# task starts from NotReady nodes (and "All nodes Ready" is not a free point)
kubectl wait --for=condition=Ready=false node --all --timeout=180s >/dev/null \
  || echo "WARNING: some nodes are still Ready"
echo "CNI removed. Pod CIDR of the cluster: ${CIDR:-unknown}"
