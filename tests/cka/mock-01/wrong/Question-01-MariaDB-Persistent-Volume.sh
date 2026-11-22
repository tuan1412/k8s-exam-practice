# storageClassName "" never matches a PV that has a class -> PVC Pending, Pod Pending
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  storageClassName: ""
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 250Mi
YAML
sed -i 's/claimName: ""/claimName: mariadb/' /root/mariadb-deploy.yaml
kubectl apply -f /root/mariadb-deploy.yaml
sleep 10
