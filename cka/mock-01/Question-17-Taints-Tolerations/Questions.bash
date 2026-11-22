#!/bin/bash
W=$(cat /var/lib/k8s-exam-practice/q17-node 2>/dev/null || echo node01)
cat <<QUESTION
Q17 · Taints and Tolerations

- Add a taint to node ${W} so that no normal Pods can be scheduled on this node: key PERMISSION, value granted, effect NoSchedule
- Schedule a Pod named nginx with image nginx in the default namespace on node ${W}, adding the correct toleration to its spec so it can be deployed

Docs: Taints and Tolerations
[Lab] ${W} is the only worker: while it carries the taint, new Pods of other questions stay Pending. Do this question last or press Reset afterwards (it removes the taint).
QUESTION
