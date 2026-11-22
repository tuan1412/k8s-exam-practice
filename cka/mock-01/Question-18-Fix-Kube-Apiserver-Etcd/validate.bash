#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
M=/etc/kubernetes/manifests/kube-apiserver.yaml
# The target state is a healthy apiserver, so without setup every check would pass for free
if [ ! -d "$STATE_DIR/q18" ]; then
  check "Q18 lab was set up (scripts/run-question.sh -m cka/mock-01 18)" false
  finish
fi
etcd=$(grep -oE -- '--etcd-servers=\S+' $M 2>/dev/null)
check "kube-apiserver --etcd-servers uses the etcd client port 2379 ($etcd)" \
  bash -c '[[ "$1" == *:2379* && "$1" != *:2380* ]]' _ "$etcd"
ok=0; for _ in 1 2 3 4 5 6; do kubectl get --raw /readyz >/dev/null 2>&1 && { ok=1; break; }; sleep 5; done
guard "kube-apiserver is ready (kubectl works)" test $ok -eq 1
guard_eq "kube-apiserver static Pod Running" \
  "$(kget -n kube-system pod -l component=kube-apiserver -ojsonpath='{.items[0].status.phase}')" "Running"
finish
