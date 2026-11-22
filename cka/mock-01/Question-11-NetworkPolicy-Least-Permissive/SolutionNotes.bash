# Q11 — Solution
cd /root/network-policies && cat network-policy-*.yaml
# policy-x: podSelector {} + ingress [{}]          -> allows EVERYTHING to every backend Pod
# policy-y: frontend namespace OR ipBlock 172.16/16 -> also opens a whole IP range
# policy-z: frontend namespace OR app=frontend Pods, TCP 80 only, only app=backend Pods  -> least permissive
kubectl get pod -n frontend --show-labels       # app=frontend
kubectl get pod -n backend --show-labels        # app=backend
kubectl apply -f /root/network-policies/network-policy-3.yaml

kubectl -n frontend exec deploy/frontend-deployment -- curl -s -m 5 backend-service.backend   # nginx page

# Traps: "- {}" in ingress means allow all; an ipBlock is an extra source, not a restriction;
#        apply exactly one file — a second, more open policy would be OR-ed with it.
