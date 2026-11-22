SC=$(kubectl get pv mariadb-pv -ojsonpath='{.spec.storageClassName}')
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  storageClassName: "$SC"
  volumeName: mariadb-pv
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 250Mi
YAML
sed -i 's/claimName: ""/claimName: mariadb/' /root/mariadb-deploy.yaml
kubectl apply -f /root/mariadb-deploy.yaml
kubectl -n mariadb rollout status deploy mariadb --timeout=300s
