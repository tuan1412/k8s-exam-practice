#!/bin/bash
kubectl delete ns relative-fawn --ignore-not-found
rm -f /var/lib/k8s-exam-practice/q16-node
