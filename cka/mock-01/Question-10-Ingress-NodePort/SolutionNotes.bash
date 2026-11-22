# Q10 — Solution
kubectl -n echo-sound expose deploy echo --name echo-service --type NodePort --port 8080 --target-port 8080
kubectl -n echo-sound get svc echo-service                   # 8080:3xxxx/TCP
curl "$(kubectl get node node01 -ojsonpath='{.status.addresses[0].address}'):$(kubectl -n echo-sound get svc echo-service -ojsonpath='{.spec.ports[0].nodePort}')/echo?msg=hi"

kubectl -n echo-sound create ingress echo --rule="example.org/echo=echo-service:8080" --dry-run=client -oyaml
# rules[0]: host example.org, path /echo, pathType Exact (create ingress) or Prefix, backend echo-service:8080
kubectl -n echo-sound create ingress echo --rule="example.org/echo=echo-service:8080"
kubectl -n echo-sound get ingress echo

# Traps: the Service port is 8080 (not 80); the Ingress backend uses the SERVICE port 8080, not the NodePort;
#        host example.org without "http://"; path /echo, not /.
