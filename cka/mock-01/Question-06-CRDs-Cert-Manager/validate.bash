#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
R=/root/resources.yaml; S=/root/subject.yaml
mine=$(kubectl get crd -oname 2>/dev/null | sed 's|.*/||' | grep -E '\.cert-manager\.io$')
other=$(kubectl get crd -oname 2>/dev/null | sed 's|.*/||' | grep -vE '\.cert-manager\.io$')
check "$R lists every cert-manager CRD ($(echo $mine | wc -w))" \
  bash -c '[ -n "$1" ] && for c in $1; do grep -q "$c" '"$R"' || exit 1; done' _ "$mine"
check "$R lists no other CRDs" \
  bash -c '[ -s '"$R"' ] && for c in $1; do ! grep -q "$c" '"$R"' || exit 1; done' _ "$other"
check "$S documents Certificate spec.subject (organizationalUnits, serialNumber...)" \
  bash -c "grep -q organizationalUnits $S && grep -q serialNumber $S"
check "$S is the subject field itself, not the whole spec" \
  bash -c "[ -s $S ] && ! grep -qE '^\s+(dnsNames|secretName|issuerRef)\b' $S"
finish
