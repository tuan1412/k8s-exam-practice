#!/bin/bash
cat <<'QUESTION'
Q6 · CRDs

Verify the cert-manager application which has been deployed in the cluster.

- Create a list of all cert-manager Custom Resource Definitions (CRDs) and save it to /root/resources.yaml
- Using kubectl, extract the documentation for the subject specification field of the Certificate Custom Resource and save it to /root/subject.yaml

You may use any output format that kubectl supports.

Docs: Custom Resources · kubectl explain
QUESTION
