#!/bin/bash
kubectl delete ns wordpress --ignore-not-found
rm -f /var/lib/k8s-exam-practice/q4-node
