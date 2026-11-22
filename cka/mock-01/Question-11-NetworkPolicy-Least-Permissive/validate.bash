#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
check_eq "NetworkPolicies in backend: only policy-z (least permissive)" \
  "$(kget -n backend networkpolicy -ojsonpath='{.items[*].metadata.name}')" "policy-z"
check_eq "policy-z unchanged: app=backend, from ns frontend | app=frontend, TCP 80" \
  "$(kget -n backend networkpolicy policy-z -ojsonpath='{.spec.podSelector.matchLabels.app}|{.spec.ingress[0].from[0].namespaceSelector.matchLabels.kubernetes\.io/metadata\.name}|{.spec.ingress[0].from[1].podSelector.matchLabels.app}|{.spec.ingress[0].ports[0].protocol}/{.spec.ingress[0].ports[0].port}|{range .spec.ingress[0].from[*]}+{end}')" \
  "backend|frontend|frontend|TCP/80|++"
guard "frontend Pod still reaches backend-service:80" \
  bash -c "timeout 25 kubectl -n frontend exec deploy/frontend-deployment -- curl -s -o /dev/null -m 8 -w '%{http_code}' http://backend-service.backend | grep -q 200"
finish
