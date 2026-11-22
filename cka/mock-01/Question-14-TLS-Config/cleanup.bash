#!/bin/bash
kubectl delete ns nginx-static --ignore-not-found
sed -i '/ckaquestion\.k8s\.local/d' /etc/hosts
