#!/bin/bash
# Q6 — cert-manager CRDs installed (v1.14.0 unless cert-manager is already there; needs internet)
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
if ! kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  echo "Installing cert-manager CRDs v1.14.0..."
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.crds.yaml >/dev/null
  mkdir -p "$STATE_DIR" && touch "$STATE_DIR/q6-installed-crds"
fi
kubectl wait --for=condition=Established crd/certificates.cert-manager.io --timeout=60s >/dev/null
# the OpenAPI schema used by "kubectl explain" is published a little after the CRD is Established,
# and after a reset the schema of the deleted CRD can still answer for a moment: wait until it stays
ok=0
for _ in $(seq 60); do
  if kubectl explain certificate.spec.subject >/dev/null 2>&1; then ok=$((ok + 1)); else ok=0; fi
  [ $ok -lt 3 ] || break
  sleep 2
done
rm -f /root/resources.yaml /root/subject.yaml
echo "cert-manager CRDs: $(kubectl get crd -oname | grep -c 'cert-manager.io')"
