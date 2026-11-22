#!/bin/bash
cat <<'QUESTION'
Q3 · Sidecar Container

Update the existing wordpress Deployment in the default namespace, adding a sidecar container named sidecar using the busybox:stable image to the existing Pod.

The new sidecar container has to run the following command:

/bin/sh -c "tail -f /var/log/wordpress.log"

Use a volume mounted at /var/log to make the log file wordpress.log available to the co-located container.

Docs: Sidecar Containers
QUESTION
