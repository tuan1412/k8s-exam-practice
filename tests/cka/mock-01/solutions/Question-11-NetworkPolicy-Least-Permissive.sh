kubectl apply -f /root/network-policies/network-policy-3.yaml
kubectl -n frontend rollout status deploy frontend-deployment --timeout=180s
kubectl -n backend rollout status deploy backend-deployment --timeout=180s
sleep 5
