kubectl -n nginx-static get cm nginx-config -oyaml | sed 's/ssl_protocols TLSv1.2 TLSv1.3;/ssl_protocols TLSv1.3;/' | kubectl apply -f -
echo "$(kubectl -n nginx-static get svc nginx-static -ojsonpath='{.spec.clusterIP}') ckaquestion.k8s.local" >> /etc/hosts
kubectl -n nginx-static rollout restart deploy nginx-static
kubectl -n nginx-static rollout status deploy nginx-static --timeout=180s
sleep 3
