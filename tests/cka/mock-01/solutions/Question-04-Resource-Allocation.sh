source "$(dirname "$0")/../../../../scripts/lib/lab-lib.sh"
W=$(cat /var/lib/k8s-exam-practice/q4-node)
kubectl -n wordpress scale deploy wordpress --replicas 0
kubectl -n wordpress wait --for=delete pod -l app=wordpress --timeout=120s
alloc_cpu=$(to_milli "$(kubectl get node "$W" -ojsonpath='{.status.allocatable.cpu}')")
alloc_mem=$(to_bytes "$(kubectl get node "$W" -ojsonpath='{.status.allocatable.memory}')")
used=$(kubectl describe node "$W" | awk '/^Allocated resources/ {s=1} s && $1=="cpu" {c=$2} s && $1=="memory" {print c, $2; exit}')
cpu=$(( (alloc_cpu - $(to_milli "${used% *}")) * 80 / 100 / 3 ))m
mem=$(( (alloc_mem - $(to_bytes "${used#* }")) * 80 / 100 / 3 / 1048576 ))Mi
echo "per Pod: cpu $cpu memory $mem"
R="{\"requests\":{\"cpu\":\"$cpu\",\"memory\":\"$mem\"},\"limits\":{\"cpu\":\"$cpu\",\"memory\":\"$mem\"}}"
kubectl -n wordpress patch deploy wordpress --type=json -p "[
  {\"op\":\"add\",\"path\":\"/spec/template/spec/initContainers/0/resources\",\"value\":$R},
  {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/resources\",\"value\":$R}]"
kubectl -n wordpress scale deploy wordpress --replicas 3
kubectl -n wordpress rollout status deploy wordpress --timeout=300s
