#!/bin/bash
kubectl delete ns frontend backend --ignore-not-found
rm -rf /root/network-policies
