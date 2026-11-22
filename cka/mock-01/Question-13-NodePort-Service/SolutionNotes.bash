# Q13 — Solution
kubectl -n relative edit deploy nodeport-deployment
# containers[0]:
#   ports:
#   - name: http
#     containerPort: 80
#     protocol: TCP
kubectl -n relative rollout status deploy nodeport-deployment

kubectl -n relative expose deploy nodeport-deployment --name nodeport-service --type NodePort \
  --port 80 --target-port http --protocol TCP --dry-run=client -oyaml > 13_svc.yaml
vim 13_svc.yaml          # ports[0].nodePort: 30080
kubectl apply -f 13_svc.yaml
kubectl -n relative get svc,endpointslices
curl -s -o /dev/null -w '%{http_code}\n' http://node01:30080      # 200

# Traps: expose has no --node-port flag: edit the YAML; the nodePort must be in 30000-32767;
#        the Service selector must match the Pod labels (app=nodeport-deployment).
