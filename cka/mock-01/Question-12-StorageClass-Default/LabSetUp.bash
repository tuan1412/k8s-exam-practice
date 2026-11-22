#!/bin/bash
# Q12 — remember the current default StorageClass (cleanup restores it), no local-storage yet
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
kubectl delete sc local-storage --ignore-not-found >/dev/null
mkdir -p "$STATE_DIR"
cur=$(default_sc)
[ -z "$cur" ] || echo "$cur" > "$STATE_DIR/q12-default-sc"
echo "Current default StorageClass: ${cur:-none}"
