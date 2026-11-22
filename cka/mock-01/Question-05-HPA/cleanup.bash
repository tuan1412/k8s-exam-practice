#!/bin/bash
kubectl delete ns autoscale --ignore-not-found
# metrics-server stays: other questions use it too
