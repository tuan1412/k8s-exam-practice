#!/bin/bash
cat <<'QUESTION'
Q2 · Argo CD Helm template

Install Argo CD in the cluster using Helm while ensuring the CRDs are not installed (as they are pre-installed):

- Add the official Argo CD Helm repository with the name argocd (https://argoproj.github.io/argo-helm)
- Create a namespace called argocd
- Generate a Helm template from the Argo CD chart version 7.7.3 for the argocd namespace
- Ensure that CRDs are not installed by configuring the chart accordingly
- Save the generated YAML manifest to /root/argo-helm.yaml

Docs: Helm Docs
QUESTION
