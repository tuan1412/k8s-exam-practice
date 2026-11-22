#!/bin/bash
W=$(cat /var/lib/k8s-exam-practice/q4-node 2>/dev/null || echo node01)
cat <<QUESTION
Q4 · Resource Allocation

You are managing a WordPress application running in the Kubernetes cluster: Deployment wordpress in namespace wordpress, whose 3 Pods run on node ${W}. Your task is to adjust the Pod resource requests and limits to ensure stable operation.

- Scale down the wordpress Deployment to 0 replicas
- Edit the Deployment and divide the node's resources evenly across all 3 Pods
- Assign fair and equal CPU and memory to each Pod
- Add sufficient overhead to avoid node instability
- Ensure both the init containers and the main containers use exactly the same resource requests and limits
- After making the changes, scale the Deployment back to 3 replicas

Docs: Resource Management for Pods and Containers
[Lab] The node also runs Pods of the other questions: kubectl describe node ${W} shows its Allocatable and the Allocated resources already requested.
QUESTION
