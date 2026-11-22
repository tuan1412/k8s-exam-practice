# Q1 — Solution
kubectl get pv                       # mariadb-pv: Available, note its STORAGECLASS
kubectl get pv mariadb-pv -oyaml | grep -E 'storageClassName|capacity|accessModes' -A1

cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  storageClassName: local-path   # = the PV's class (kubectl get pv); "" would never match it
  volumeName: mariadb-pv         # optional, pins the claim to this PV
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 250Mi
YAML

vim ~/mariadb-deploy.yaml            # claimName: mariadb
kubectl apply -f ~/mariadb-deploy.yaml
kubectl -n mariadb get pvc,pod       # PVC Bound to mariadb-pv, pod Running
kubectl -n mariadb rollout status deploy mariadb

# Traps: storageClassName must equal the PV's class (or be omitted while that class is the default);
#        storageClassName: "" only binds PVs without a class;
#        with a WaitForFirstConsumer class the PVC stays Pending until the Pod exists — that is normal.
