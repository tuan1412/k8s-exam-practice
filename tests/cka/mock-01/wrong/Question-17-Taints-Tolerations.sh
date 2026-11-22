# wrong toleration value: the scheduler keeps the Pod Pending
W=$(cat /var/lib/k8s-exam-practice/q17-node)
kubectl taint node "$W" PERMISSION=granted:NoSchedule --overwrite
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: default
spec:
  nodeSelector:
    kubernetes.io/hostname: $W
  tolerations:
  - key: PERMISSION
    operator: Equal
    value: "true"
    effect: NoSchedule
  containers:
  - name: nginx
    image: nginx
YAML
sleep 10
