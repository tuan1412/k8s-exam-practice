#!/bin/bash
# Q17 — nothing to create: remember the worker, make sure it has no PERMISSION taint yet
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
W=$(pick_worker)
mkdir -p "$STATE_DIR" && echo "$W" > "$STATE_DIR/q17-node"
kubectl taint node "$W" PERMISSION- >/dev/null 2>&1 || true
kubectl -n default delete pod nginx --ignore-not-found >/dev/null
echo "Worker for Q17: $W"
