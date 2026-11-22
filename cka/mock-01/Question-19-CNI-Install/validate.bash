#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
# The target state is a working cluster, so without setup every check would pass for free
if [ ! -f "$STATE_DIR/q19-cni-removed" ]; then
  check "Q19 lab was set up (scripts/run-question.sh -m cka/mock-01 19)" false
  finish
fi
CIDR=$(cat "$STATE_DIR/q19-cni-removed")
nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
check "Calico installed from tigera-operator.yaml (operator Deployment available)" \
  bash -c "[ \"\$(kubectl -n tigera-operator get deploy tigera-operator -ojsonpath='{.status.availableReplicas}')\" -ge 1 ]"
check_eq "calico-node (NetworkPolicy-capable CNI) ready on all $nodes nodes" \
  "$(kget -n calico-system ds calico-node -ojsonpath='{.status.numberReady}')" "$nodes"
check_eq "Calico IP pool = the cluster's podSubnet" \
  "$(kget installation default -ojsonpath='{.spec.calicoNetwork.ipPools[*].cidr}')" "$CIDR"
check "All nodes Ready" \
  bash -c "! kubectl get nodes --no-headers | awk '{print \$2}' | grep -vx Ready"
# right after the host starts (End exam grades host by host), nodes are Ready before Calico and
# CoreDNS serve again: wait for them, then give the probe a few tries
probe() {
  kubectl -n calico-system rollout status ds/calico-node --timeout=90s >/dev/null 2>&1
  kubectl -n kube-system rollout status deploy/coredns --timeout=60s >/dev/null 2>&1
  for _ in 1 2 3; do
    timeout 120 kubectl run "q19-probe-$RANDOM" --image=busybox:stable --restart=Never --rm -i --quiet \
      --pod-running-timeout=90s --command -- nslookup kubernetes.default.svc.cluster.local && return 0
    sleep 5
  done
  return 1
}
check "A new Pod gets a network and resolves kubernetes.default via CoreDNS" probe
finish
