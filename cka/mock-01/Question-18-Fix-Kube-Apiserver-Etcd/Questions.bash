#!/bin/bash
cat <<'QUESTION'
Q18 · Fix kube-apiserver

After a cluster migration, the controlplane kube-apiserver is not coming up. Before the migration, etcd was external and in HA; after the migration, the kube-apiserver was pointed to the etcd peer port 2380.

- Fix it, so that kube-apiserver works and kubectl can talk to the cluster again

Docs: Operating etcd clusters for Kubernetes · Static Pods
[Lab] Set up alone: until you fix it, kubectl fails for every question.
[Lab] The kubelet of this lab node sometimes misses a manifest edit (a known quirk of kubelet in a container): if kube-apiserver is not back within about a minute after your fix, run `systemctl restart kubelet`.
QUESTION
