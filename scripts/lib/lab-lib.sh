#!/usr/bin/env bash
# Helpers for LabSetUp.bash / cleanup.bash / validate.bash. Sourced, not executed.

STATE_DIR=/var/lib/k8s-exam-practice

# pick_worker -> name of the first schedulable worker node (no control-plane role),
# or the first node when there is none (single-node clusters, e.g. CI)
pick_worker() {
  local w
  w=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  [ -n "$w" ] || w=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
  echo "$w"
}

# node_ip <node> -> InternalIP
node_ip() {
  kubectl get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'
}

# default_sc -> names of the StorageClasses marked as default (space separated)
default_sc() {
  kubectl get sc -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{" "}{end}' 2>/dev/null | xargs
}

ensure_helm() {
  command -v helm >/dev/null && return
  echo "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null
}

# metrics-server with --kubelet-insecure-tls (kubeadm labs lack kubelet serving certs)
ensure_metrics_server() {
  kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1 && return
  echo "Installing metrics-server..."
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null
  kubectl -n kube-system patch deploy metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
}

# to_milli <cpu quantity> -> millicores ("250m" -> 250, "1.5" -> 1500)
to_milli() {
  awk -v q="$1" 'BEGIN{
    if (q == "") { print 0; exit }
    if (q ~ /m$/) { sub(/m$/, "", q); printf "%d\n", q; exit }
    printf "%d\n", q * 1000 }'
}

# to_bytes <memory quantity> -> bytes ("300Mi", "1Gi", "1843520Ki", "500M", "1e9")
to_bytes() {
  awk -v q="$1" 'BEGIN{
    if (q == "") { print 0; exit }
    n = q; u = q; sub(/[A-Za-z]+$/, "", n); sub(/^[0-9.eE+-]+/, "", u)
    m["Ki"]=1024; m["Mi"]=1048576; m["Gi"]=1073741824; m["Ti"]=1099511627776
    m["k"]=1000; m["K"]=1000; m["M"]=1e6; m["G"]=1e9; m["T"]=1e12; m[""]=1
    printf "%.0f\n", n * m[u] }'
}

# ensure_ns <namespace>: create it if missing and wait for its "default" ServiceAccount.
# Right after a namespace is created a bare Pod is refused until the controller has made it
# ("serviceaccount "default" not found"), which happens on a freshly built host.
ensure_ns() {
  kubectl create ns "$1" --dry-run=client -oyaml | kubectl apply -f - >/dev/null
  local i
  for i in $(seq 60); do kubectl -n "$1" get sa default >/dev/null 2>&1 && return 0; sleep 1; done
  echo "WARNING: namespace $1 has no default ServiceAccount after 60s" >&2
}
