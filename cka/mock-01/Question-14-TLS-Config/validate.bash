#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
H=ckaquestion.k8s.local
ip=$(kget -n nginx-static svc nginx-static -ojsonpath='{.spec.clusterIP}')
proto=$(kget -n nginx-static cm nginx-config -ojsonpath='{.data.nginx\.conf}' | sed -nE 's/^\s*ssl_protocols\s+([^;]*);.*/\1/p' | xargs)
check_eq "ConfigMap nginx-config: ssl_protocols TLSv1.3 only" "$proto" "TLSv1.3"
check_eq "/etc/hosts: $H -> Service IP" \
  "$(awk -v h=$H '{for (i = 2; i <= NF; i++) if ($i == h) print $1}' /etc/hosts | tail -1)" "$ip"
check "TLS 1.3 works (Hello TLS) and TLS 1.2 is rejected" \
  bash -c "[ -n '$ip' ] && curl -sk -m 5 --tlsv1.3 --resolve $H:443:$ip https://$H/ | grep -q 'Hello TLS' \
    && ! curl -sk -m 5 --tls-max 1.2 --resolve $H:443:$ip https://$H/ >/dev/null 2>&1"
finish
