# Q18 — Solution (as root on the controlplane)
kubectl get nodes                      # connection refused / timeout
crictl ps -a | grep kube-apiserver     # Exited, restarting
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail
#   ... dial tcp 127.0.0.1:2380 ... / "transport: authentication handshake failed"
ls /var/log/pods/ | grep apiserver     # logs also here

grep -- --etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml   # https://127.0.0.1:2380
vim /etc/kubernetes/manifests/kube-apiserver.yaml                     # 2380 -> 2379 (client port)
# kubelet recreates the static Pod by itself (about 30-60s); watch it:
watch crictl ps --name kube-apiserver
kubectl get nodes

# Traps: 2379 = etcd CLIENT port (what kube-apiserver needs), 2380 = PEER port (etcd <-> etcd);
#        never keep a backup copy inside /etc/kubernetes/manifests (kubelet runs every file there);
#        kubectl does not work while you debug: use crictl and /var/log/pods.
