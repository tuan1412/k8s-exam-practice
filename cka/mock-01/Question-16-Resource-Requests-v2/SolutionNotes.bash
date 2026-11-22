# Q16 — Solution
kubectl describe node node01 | grep -A6 -E '^Allocatable|^Allocated resources'
kubectl -n relative-fawn get pod -o custom-columns=NAME:.metadata.name,CPU:.spec.containers[0].resources.requests.cpu,MEM:.spec.containers[0].resources.requests.memory
# available for wordpress = Allocatable - requests of the OTHER Pods (Allocated minus 3 x 100m/100Mi)
# per Pod = available / 3, minus some overhead, and never above the limits (300m / 500Mi)
#   e.g. available cpu 900m, memory 1200Mi  ->  250m / 350Mi

kubectl -n relative-fawn scale deploy wordpress --replicas 0       # room for the bigger Pods
kubectl -n relative-fawn set resources deploy wordpress -c wordpress --requests=cpu=250m,memory=350Mi
kubectl -n relative-fawn scale deploy wordpress --replicas 3
kubectl -n relative-fawn rollout status deploy wordpress
kubectl -n relative-fawn get pod                                   # 3/3 Running

# Traps: requests > limits is rejected; a rolling update needs room for one extra Pod (maxSurge),
#        so scaling to 0 first avoids a Pending surge Pod; don't touch the limits.
