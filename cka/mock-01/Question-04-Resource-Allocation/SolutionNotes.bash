# Q4 — Solution
kubectl -n wordpress scale deploy wordpress --replicas 0
kubectl describe node node01 | grep -A6 -E '^Allocatable|^Allocated resources'
# Example: Allocatable cpu 2 / memory 1912Mi; already requested by other Pods: cpu 450m / memory 240Mi
#   free:     cpu 1550m,           memory 1672Mi
#   per Pod:  ~ (free - overhead) / 3  ->  cpu 450m, memory 480Mi
# Init containers run BEFORE the app container, not alongside it: a Pod's effective request is
# max(init, sum(app containers)), so identical values for both do not double the Pod's request.

kubectl -n wordpress edit deploy wordpress
# for BOTH initContainers[init-setup] and containers[wordpress]:
#   resources:
#     requests:
#       cpu: 450m
#       memory: 480Mi
#     limits:
#       cpu: 450m
#       memory: 480Mi

kubectl -n wordpress scale deploy wordpress --replicas 3
kubectl -n wordpress rollout status deploy wordpress
kubectl -n wordpress get pod -owide            # 3/3 Running

# Traps: dividing the whole Allocatable by 3 ignores the Pods already on the node -> the 3rd Pod stays
#        Pending (Insufficient cpu/memory); forgetting the init container; memory limit too small
#        for apache -> OOMKilled.
