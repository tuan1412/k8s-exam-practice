# Service on port 80 and an Ingress for / instead of /echo
kubectl -n echo-sound expose deploy echo --name echo-service --type NodePort --port 80 --target-port 8080
kubectl -n echo-sound create ingress echo --rule="example.org/*=echo-service:80"
