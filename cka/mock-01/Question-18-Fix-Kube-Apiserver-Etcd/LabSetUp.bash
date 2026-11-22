#!/bin/bash
# Q18 — DESTRUCTIVE: point kube-apiserver at the etcd peer port 2380 instead of the client port 2379
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
M=/etc/kubernetes/manifests/kube-apiserver.yaml
[ -f $M ] || { echo "$M not found: run this on the controlplane node"; exit 1; }
mkdir -p "$STATE_DIR/q18"
grep -q -- '--etcd-servers=.*:2380' $M || cp $M "$STATE_DIR/q18/kube-apiserver.yaml"
sed -i -E '/--etcd-servers=/ s/:2379/:2380/g' $M
# exam-hostctl: this host's cluster is down on purpose, do not wait for it when starting the host
touch /etc/exam-cluster-broken
grep -- '--etcd-servers' $M
echo "kube-apiserver restarts with the wrong etcd port within ~30s; kubectl will then fail."
