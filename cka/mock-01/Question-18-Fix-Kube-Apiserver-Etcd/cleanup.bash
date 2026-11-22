#!/bin/bash
# Put the original manifest back if the apiserver is still pointed at 2380
S=/var/lib/k8s-exam-practice/q18; M=/etc/kubernetes/manifests/kube-apiserver.yaml
if [ -f $S/kube-apiserver.yaml ] && grep -q -- '--etcd-servers=.*:2380' $M; then
  cp $S/kube-apiserver.yaml $M
  echo "Restored $M, waiting for kube-apiserver..."
  for _ in $(seq 60); do kubectl get --raw /readyz >/dev/null 2>&1 && break; sleep 5; done
fi
rm -rf $S
