#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
D="-n relative deploy nodeport-deployment"; S="-n relative svc nodeport-service"
check_eq "Container port 80 named http, TCP" \
  "$(kget $D -ojsonpath='{.spec.template.spec.containers[0].ports[?(@.containerPort==80)].name}/{.spec.template.spec.containers[0].ports[?(@.containerPort==80)].protocol}')" "http/TCP"
guard_eq "Rollout complete (2/2 updated and available)" \
  "$(kget $D -ojsonpath='{.status.updatedReplicas}/{.status.availableReplicas}/{.status.replicas}')" "2/2/2"
check_eq "Service nodeport-service: NodePort, TCP 80 -> nodePort 30080" \
  "$(kget $S -ojsonpath='{.spec.type} {.spec.ports[0].protocol} {.spec.ports[0].port} {.spec.ports[0].nodePort}')" "NodePort TCP 80 30080"
check "targetPort is the container port (80 or http)" \
  bash -c '[[ "$1" == 80 || "$1" == http ]]' _ "$(kget $S -ojsonpath='{.spec.ports[0].targetPort}')"
check_eq "Service has the 2 Pods as ready endpoints" \
  "$(kget -n relative endpointslices -l kubernetes.io/service-name=nodeport-service -ojsonpath='{.items[*].endpoints[?(@.conditions.ready==true)].addresses[*]}' | wc -w | tr -d ' ')" "2"
check "curl <node-ip>:30080 answers 200" \
  bash -c '[ "$(curl -s -o /dev/null -m 10 -w "%{http_code}" "http://$1:30080/")" == 200 ]' _ "$(node_ip "$(pick_worker)")"
finish
