W=$(cat /var/lib/k8s-exam-practice/q17-node)
kubectl taint node "$W" PERMISSION=granted:NoSchedule --overwrite
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: default
spec:
  nodeName: $W
  tolerations:
  - key: PERMISSION
    operator: Equal
    value: granted
    effect: NoSchedule
  containers:
  - name: nginx
    image: nginx
YAML
kubectl -n default wait --for=condition=Ready pod/nginx --timeout=180s
