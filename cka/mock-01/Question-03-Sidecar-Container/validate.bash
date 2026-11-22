#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
D="-n default deploy wordpress"
# the sidecar may be a regular container or a native sidecar (initContainer with restartPolicy: Always)
c='{.spec.template.spec.containers[?(@.name=="sidecar")]'; i='{.spec.template.spec.initContainers[?(@.name=="sidecar")]'
img="$(kget $D -ojsonpath="${c}.image}")$(kget $D -ojsonpath="${i}.image}")"
cmd="$(kget $D -ojsonpath="${c}.command[*]} ${c}.args[*]}")$(kget $D -ojsonpath="${i}.command[*]} ${i}.args[*]}")"
check_eq "Container sidecar uses image busybox:stable" "$img" "busybox:stable"
check "sidecar runs tail -f /var/log/wordpress.log" \
  bash -c '[[ "$1" =~ tail\ +-[fF]\ +/var/log/wordpress.log ]]' _ "$cmd"
vol_main=$(kget $D -ojsonpath='{.spec.template.spec.containers[?(@.name=="wordpress")].volumeMounts[?(@.mountPath=="/var/log")].name}')
vol_side="$(kget $D -ojsonpath="${c}.volumeMounts[?(@.mountPath==\"/var/log\")].name}")$(kget $D -ojsonpath="${i}.volumeMounts[?(@.mountPath==\"/var/log\")].name}")"
check "wordpress and sidecar mount the same volume at /var/log" \
  bash -c '[ -n "$1" ] && [ "$1" == "$2" ]' _ "$vol_main" "$vol_side"
guard_eq "wordpress container still writes the log (command unchanged)" \
  "$(kget $D -ojsonpath='{.spec.template.spec.containers[?(@.name=="wordpress")].command[2]}')" \
  "while true; do echo 'WordPress is running...' >> /var/log/wordpress.log; sleep 5; done"
guard "Rollout complete (new Pod with sidecar available)" \
  timeout 90 kubectl -n default rollout status deploy wordpress --timeout=80s
pod=$(kubectl -n default get pod -l app=wordpress --field-selector status.phase=Running \
  -ojsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.metadata.name}|{.spec.containers[*].name} {.spec.initContainers[*].name}{"\n"}{end}' 2>/dev/null \
  | awk -F'|' '$1 == "" && $3 ~ /(^| )sidecar( |$)/ {print $2; exit}')
check "The sidecar sees the WordPress log lines in /var/log/wordpress.log" \
  bash -c '[ -n "$1" ] && timeout 20 kubectl -n default exec "$1" -c sidecar -- grep -q "WordPress is running" /var/log/wordpress.log' _ "$pod"
finish
