#!/bin/bash
cat <<'QUESTION'
Q7 · PriorityClass

You're working in a Kubernetes cluster with an existing Deployment named busybox-logger running in the priority namespace. The cluster already has at least one user-defined PriorityClass.

- Create a new PriorityClass named high-priority for user workloads. The value of this class should be exactly one less than the highest existing user-defined PriorityClass
- Patch the existing Deployment busybox-logger in the priority namespace to use the newly created high-priority class

Docs: kubectl create priorityclass · Update API Objects in Place Using kubectl patch
QUESTION
