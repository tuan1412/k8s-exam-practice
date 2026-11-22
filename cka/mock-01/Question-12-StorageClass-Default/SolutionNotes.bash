# Q12 — Solution
kubectl get sc                         # local-path (default)
cat <<'YAML' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
YAML

kubectl patch sc local-storage -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl patch sc local-path    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl get sc                         # only local-storage shows (default)

# Traps: the annotation value is the STRING "true"/"false" (quoted in JSON);
#        two defaults are allowed by the API (the newest wins) but the task wants exactly one;
#        provisioner and volumeBindingMode are immutable: delete + recreate if wrong.
