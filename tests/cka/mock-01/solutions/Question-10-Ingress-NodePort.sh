kubectl -n echo-sound expose deploy echo --name echo-service --type NodePort --port 8080 --target-port 8080
kubectl -n echo-sound create ingress echo --rule="example.org/echo=echo-service:8080"
kubectl -n echo-sound rollout status deploy echo --timeout=180s
sleep 5
