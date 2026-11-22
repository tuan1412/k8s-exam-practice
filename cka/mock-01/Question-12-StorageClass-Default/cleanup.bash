#!/bin/bash
S=/var/lib/k8s-exam-practice/q12-default-sc
kubectl delete sc local-storage --ignore-not-found
# give the default back to the class(es) that had it before the lab
for sc in $(cat $S 2>/dev/null); do
  kubectl patch sc "$sc" -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null 2>&1 || true
done
rm -f $S
