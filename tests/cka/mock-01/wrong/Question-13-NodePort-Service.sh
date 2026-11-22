# no named container port and a random NodePort
kubectl -n relative expose deploy nodeport-deployment --name nodeport-service --type NodePort --port 80
