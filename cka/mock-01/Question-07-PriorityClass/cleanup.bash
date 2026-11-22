#!/bin/bash
kubectl delete ns priority --ignore-not-found
kubectl delete priorityclass high-priority user-critical user-batch --ignore-not-found
