#!/bin/bash
cat <<'QUESTION'
Q19 · CNI and NetworkPolicy

Install and configure a Container Network Interface (CNI) of your choice that meets the specified requirements. Choose one of the following options:

- Flannel (v0.26.1) using the manifest kube-flannel.yml (https://github.com/flannel-io/flannel/releases/download/v0.26.1/kube-flannel.yml)
- Calico (v3.28.2) using the manifest tigera-operator.yaml (https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/tigera-operator.yaml)

The CNI you choose must:

- Let Pods communicate with each other
- Support NetworkPolicy enforcement
- Install from manifest

Docs: Network Plugins · Install Calico (docs.tigera.io)
[Lab] Set up alone, last: setup removed the CNI, nodes are NotReady. Pods created before keep a stale network: restart CoreDNS after installing.
QUESTION
