#!/bin/bash
rm -f /root/resources.yaml /root/subject.yaml
S=/var/lib/k8s-exam-practice/q6-installed-crds
# only remove the CRDs this lab installed, never those of a Helm-installed cert-manager
if [ -f $S ] && [ "$(kubectl get crd certificates.cert-manager.io -ojsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null)" != "Helm" ]; then
  kubectl delete crd certificaterequests.cert-manager.io certificates.cert-manager.io challenges.acme.cert-manager.io \
    clusterissuers.cert-manager.io issuers.cert-manager.io orders.acme.cert-manager.io --ignore-not-found
fi
rm -f $S
