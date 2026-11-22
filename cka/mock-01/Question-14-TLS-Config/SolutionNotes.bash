# Q14 — Solution
kubectl -n nginx-static edit cm nginx-config        # ssl_protocols TLSv1.3;
echo "$(kubectl -n nginx-static get svc nginx-static -ojsonpath='{.spec.clusterIP}') ckaquestion.k8s.local" >> /etc/hosts
kubectl -n nginx-static rollout restart deploy nginx-static
kubectl -n nginx-static rollout status deploy nginx-static

curl -vk --tls-max 1.2 https://ckaquestion.k8s.local     # alert protocol version -> fails
curl -vk --tlsv1.3 https://ckaquestion.k8s.local         # Hello TLS

# Traps: the file is mounted with subPath, so nginx never sees ConfigMap updates:
#        restart the Deployment (rollout restart) after editing;
#        use the Service ClusterIP (not a Pod IP) in /etc/hosts.
