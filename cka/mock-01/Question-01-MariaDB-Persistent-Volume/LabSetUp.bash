#!/bin/bash
# Q1 — retained PV mariadb-pv (Available), namespace mariadb, ~/mariadb-deploy.yaml with an empty claimName
set -e
source "$(dirname "$0")/../../../scripts/lib/lab-lib.sh"
# a previous attempt left the PV Bound/Released: start over
if kubectl get pv mariadb-pv >/dev/null 2>&1 && [ "$(kubectl get pv mariadb-pv -ojsonpath='{.status.phase}')" != "Available" ]; then
  bash "$(dirname "$0")/cleanup.bash" >/dev/null 2>&1
fi
kubectl create ns mariadb --dry-run=client -oyaml | kubectl apply -f - >/dev/null

# The PV carries the cluster's default StorageClass, so a PVC that omits storageClassName can bind to it
SC=$(default_sc | awk '{print $1}')
cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mariadb-pv
  labels:
    app: mariadb
spec:
  capacity:
    storage: 250Mi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  ${SC:+storageClassName: $SC}
  hostPath:
    path: /mnt/data/mariadb
YAML

cat > /root/mariadb-deploy.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mariadb
  namespace: mariadb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mariadb
  template:
    metadata:
      labels:
        app: mariadb
    spec:
      containers:
      - name: mariadb
        image: mariadb:10.6
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: rootpass
        volumeMounts:
        - name: mariadb-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mariadb-storage
        persistentVolumeClaim:
          claimName: ""
YAML
echo "PV mariadb-pv (${SC:-no StorageClass}) is Available; deployment file: /root/mariadb-deploy.yaml"
