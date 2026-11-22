#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
S="-n echo-sound svc echo-service"
check_eq "Service echo-service: NodePort, port 8080 -> 8080" \
  "$(kget $S -ojsonpath='{.spec.type} {.spec.ports[0].port}')->$(kget $S -ojsonpath='{.spec.ports[0].targetPort}')" "NodePort 8080->8080"
check "echo-service selects the echo Pods (has endpoints)" \
  bash -c '[ -n "$1" ]' _ "$(kget -n echo-sound endpointslices -l kubernetes.io/service-name=echo-service -ojsonpath='{.items[*].endpoints[*].addresses[*]}')"
np=$(kget $S -ojsonpath='{.spec.ports[0].nodePort}'); ip=$(node_ip "$(pick_worker)")
check "curl NODEIP:NODEPORT/echo answers 200" \
  bash -c '[ -n "$1" ] && [ "$(curl -s -o /dev/null -m 10 -w "%{http_code}" "http://$2:$1/echo")" == 200 ]' _ "$np" "$ip"
rules=$(kget -n echo-sound ingress echo -ojsonpath='{range .spec.rules[*]}{.host}{range .http.paths[*]}|{.path}:{.pathType}:{.backend.service.name}:{.backend.service.port.number}{end}{"\n"}{end}')
check "Ingress echo: example.org/echo -> echo-service:8080" \
  bash -c 'grep -qE "^example\.org(\|.*)?\|/echo:(Prefix|Exact|ImplementationSpecific):echo-service:8080" <<< "$1"' _ "$rules"
finish
