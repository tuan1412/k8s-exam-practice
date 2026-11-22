#!/bin/bash
for n in $(kubectl get nodes -ojsonpath='{.items[*].metadata.name}'); do
  kubectl taint node "$n" PERMISSION- >/dev/null 2>&1 || true
done
kubectl -n default delete pod nginx --ignore-not-found
rm -f /var/lib/k8s-exam-practice/q17-node
