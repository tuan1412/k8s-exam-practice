#!/bin/bash
cat <<'QUESTION'
Q5 · HorizontalPodAutoscaler

Create a new HorizontalPodAutoscaler (HPA) named apache-server in the autoscale namespace.

- The HPA must target the existing Deployment called apache-deployment in the autoscale namespace
- Set the HPA to target 50% CPU usage per Pod
- Configure the HPA to have a minimum of 1 Pod and a maximum of 4 Pods
- Set the downscale stabilization window to 30 seconds

Docs: HorizontalPodAutoscaler Walkthrough · Horizontal Pod Autoscaling
QUESTION
