#!/usr/bin/env bash
# Runs as root on controlplane and node01: containerd + kubeadm/kubelet/kubectl.
# Env: K8S_MINOR (e.g. v1.33), NODE_IP
set -euo pipefail
: "${K8S_MINOR:?}" "${NODE_IP:?}"
export DEBIAN_FRONTEND=noninteractive

swapoff -a 2>/dev/null || true   # in a container node the host has to turn swap off
sed -i '/\sswap\s/ s/^/#/' /etc/fstab

cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
# a container node cannot load modules: the host must have loaded them already
for m in overlay br_netfilter; do
  modprobe "$m" 2>/dev/null || [ -d "/sys/module/$m" ] || { echo "kernel module $m is missing"; exit 1; }
done
cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/k8s.conf >/dev/null

apt-get update -qq
apt-get install -y -qq containerd apt-transport-https ca-certificates curl wget gpg jq vim tmux man-db bash-completion iptables >/dev/null
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# The repo file name matters: the upgrade labs rewrite /etc/apt/sources.list.d/kubernetes.list
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl cri-tools >/dev/null   # kubeadm >= 1.37 no longer pulls in crictl
apt-mark hold kubelet kubeadm kubectl >/dev/null
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet
systemctl enable kubelet >/dev/null 2>&1

cat > /etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
EOF

# Same tools as the exam's ssh hosts: kubectl with k alias + Bash completion, yq, curl, wget, man
# (docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad)
YQ=v4.44.3
[ -x /usr/local/bin/yq ] || curl -fsSL -o /usr/local/bin/yq \
  "https://github.com/mikefarah/yq/releases/download/${YQ}/yq_linux_$(dpkg --print-architecture)"
chmod 755 /usr/local/bin/yq

# Ubuntu's root .bashrc leaves bash-completion off, so load it here too
sed -i '/^# >>> exam shell/,/^# <<< exam shell/d' /root/.bashrc
cat >> /root/.bashrc <<'EOF'
# >>> exam shell
if [ -z "${BASH_COMPLETION_VERSINFO-}" ] && [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
fi
source <(kubectl completion bash 2>/dev/null)
alias k=kubectl
complete -o default -F __start_kubectl k
# <<< exam shell
EOF

# The ~/.vimrc the real exam ships with (YAML-friendly indentation)
printf 'set tabstop=2\nset expandtab\nset shiftwidth=2\n' > /root/.vimrc

# Root key for ssh controlplane -> node01 (upgrade and crictl labs)
[ -f /root/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f /root/.ssh/id_ed25519
grep -q 'StrictHostKeyChecking' /root/.ssh/config 2>/dev/null \
  || printf 'Host controlplane node01\n  StrictHostKeyChecking accept-new\n' >> /root/.ssh/config
echo "k8s-node: done ($(kubeadm version -o short))"
