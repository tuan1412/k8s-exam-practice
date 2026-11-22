#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
G="-n default gateway web-gateway"; R="-n default httproute web-route"
H=gateway.web.k8s.local
check_eq "Gateway web-gateway uses GatewayClass nginx-class" "$(kget $G -ojsonpath='{.spec.gatewayClassName}')" "nginx-class"
listeners=$(kget $G -ojsonpath='{range .spec.listeners[*]}{.protocol}:{.port}:{.hostname}:{.tls.mode}:{.tls.certificateRefs[*].name}{"\n"}{end}')
check "Listener HTTPS :443 for $H" bash -c 'grep -q "^HTTPS:443:'$H':" <<< "$1"' _ "$listeners"
check "That listener terminates TLS with Secret web-tls" \
  bash -c 'grep -qE "^HTTPS:443:'$H':(Terminate)?:web-tls$" <<< "$1"' _ "$listeners"
check "HTTPRoute web-route attached to web-gateway" \
  bash -c 'grep -qw web-gateway <<< "$1"' _ "$(kget $R -ojsonpath='{.spec.parentRefs[*].name}')"
check "HTTPRoute hostname $H" bash -c 'grep -qw "'$H'" <<< "$1"' _ "$(kget $R -ojsonpath='{.spec.hostnames[*]}')"
rules=$(kget $R -ojsonpath='{range .spec.rules[*]}{range .matches[*]}{.path.type}={.path.value},{end}|{range .backendRefs[*]}{.name}:{.port},{end}{"\n"}{end}')
check "Rule: PathPrefix / -> web-service:80" bash -c 'grep -qE "(^|,)PathPrefix=/,.*\|.*web-service:80," <<< "$1"' _ "$rules"
finish
