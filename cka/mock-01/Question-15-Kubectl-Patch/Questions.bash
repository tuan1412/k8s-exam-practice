#!/bin/bash
cat <<'QUESTION'
Q15 · kubectl patch

A Deployment named resource-app exists in the patch-ns namespace. Its resource limits (CPU 200m, memory 256Mi) are too low for the expected workload.

Using ONLY kubectl patch (not kubectl edit, kubectl set or kubectl apply):

- Update the CPU limit of the nginx container to 500m
- Update the memory limit of the nginx container to 512Mi

Do not change the CPU or memory requests. The Deployment must remain available with 2 replicas.

Docs: Update API Objects in Place Using kubectl patch
[Lab] The grader reads the field managers (metadata.managedFields) to see which command changed the limits.
QUESTION
