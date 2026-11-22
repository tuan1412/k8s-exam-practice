# Q17 — Solution
kubectl taint node node01 PERMISSION=granted:NoSchedule
kubectl describe node node01 | grep -A2 Taints

kubectl run nginx --image=nginx --dry-run=client -oyaml > 17_pod.yaml
vim 17_pod.yaml
# spec:
#   nodeName: node01           # optional: the taint + toleration alone do not pin the Pod,
#   tolerations:               #           but here node01 is the only schedulable node
#   - key: PERMISSION
#     operator: Equal
#     value: granted
#     effect: NoSchedule
#   containers: ...
kubectl apply -f 17_pod.yaml
kubectl get pod nginx -owide         # Running on node01

# Traps: key/value are case-sensitive (PERMISSION, granted); the toleration effect must be NoSchedule
#        (or empty); a toleration only ALLOWS scheduling on the tainted node, it does not attract the Pod.
