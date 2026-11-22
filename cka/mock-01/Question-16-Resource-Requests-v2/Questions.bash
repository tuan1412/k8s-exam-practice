#!/bin/bash
W=$(cat /var/lib/k8s-exam-practice/q16-node 2>/dev/null || echo node01)
cat <<QUESTION
Q16 · Resource Requests v2

A WordPress Deployment named wordpress in namespace relative-fawn has 3 replicas, all running on node ${W}.

- Edit the WordPress Deployment so that each Pod's resource requests equally divide the node's available resources among the 3 replicas
- Limits do not need to be changed
- All 3 replicas must be Running afterwards

Docs: Resource Management for Pods and Containers
[Lab] Q4's Pods run on the same node. Requests can never exceed the limits (300m CPU, 500Mi memory).
[Lab] A rolling update needs room for one extra Pod while the old ones still hold their requests: leave some headroom, or scale to 0 and back to 3.
QUESTION
