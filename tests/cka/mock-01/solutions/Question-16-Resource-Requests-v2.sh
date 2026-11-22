source "$(dirname "$0")/../../../../scripts/lib/lab-lib.sh"
W=$(cat /var/lib/k8s-exam-practice/q16-node)
kubectl -n relative-fawn scale deploy wordpress --replicas 0
kubectl -n relative-fawn wait --for=delete pod -l app=wordpress --timeout=120s
alloc_cpu=$(to_milli "$(kubectl get node "$W" -ojsonpath='{.status.allocatable.cpu}')")
alloc_mem=$(to_bytes "$(kubectl get node "$W" -ojsonpath='{.status.allocatable.memory}')")
used=$(kubectl describe node "$W" | awk '/^Allocated resources/ {s=1} s && $1=="cpu" {c=$2} s && $1=="memory" {print c, $2; exit}')
cpu=$(( (alloc_cpu - $(to_milli "${used% *}")) * 85 / 100 / 3 )); [ $cpu -le 300 ] || cpu=300
mem=$(( (alloc_mem - $(to_bytes "${used#* }")) * 85 / 100 / 3 / 1048576 )); [ $mem -le 500 ] || mem=500
echo "per Pod: cpu ${cpu}m memory ${mem}Mi"
kubectl -n relative-fawn set resources deploy wordpress -c wordpress --requests=cpu=${cpu}m,memory=${mem}Mi
kubectl -n relative-fawn scale deploy wordpress --replicas 3
kubectl -n relative-fawn rollout status deploy wordpress --timeout=300s
