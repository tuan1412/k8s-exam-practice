#!/usr/bin/env bash
# The exam hosts of the simulator: one small kubeadm cluster per host, as Incus system
# containers on the desktop VM (simulator/lab.sh) or on any Ubuntu 24.04 machine.
#
# Each */mock-*/hosts.txt maps questions to hosts, like the exam's "ssh <host>". A host is
# a cluster: the container <host> is its controlplane, <host>-node01.. its workers. Inside
# a cluster the nodes keep the names the labs expect (controlplane, node01). A host with
# several questions is shared; a host with one question is reset by restoring its "fresh"
# snapshot. To save memory only the shared hosts of the exam in use and one other host
# run at a time (EXAM_KEEP_RUNNING=all keeps every host running).
#
# Usage (as root):
#   exam-hosts.sh install                 Incus, kernel modules, network, profile
#   exam-hosts.sh build [mock [host..]]   k8s-base + every host of every exam (+ snapshots),
#                                         or only the hosts of one exam, or only some of those
#   exam-hosts.sh use <mock> <host>       make sure <host> runs (stops other hosts)
#   exam-hosts.sh reset <host>            restore the host's "fresh" snapshot
#   exam-hosts.sh e2e <mock> [question|host..]  run tests/run-e2e.sh on each question's host
#   exam-hosts.sh e2e-plan                JSON list of {mock, host, questions} for CI, one job per
#                                         entry: one question per exam (E2E_ALL=1: every question)
#   exam-hosts.sh status | mem | nodes <host> | delete <host>
# Env: K8S_MINOR, EXAM_REPO, E2E_ALL, CP_MEM=2560MiB NODE_MEM=2GiB CPUS=2, EXAM_KEEP_RUNNING, DPKG_UNSAFE_IO=1, EXAM_TRACE=1, APT_MIRROR, APT_CACHE_DIR
set -euo pipefail

SELF="$(readlink -f "$0")"
REPO="${EXAM_REPO:-$(cd "$(dirname "$SELF")/../.." && pwd)}"
NET=10.123.0       # incusbr0 is $NET.1/24, hosts get static addresses from $NET.11
IMAGE="${IMAGE:-images:ubuntu/24.04}"
POOL_SIZE="${POOL_SIZE:-40GiB}"
CP_MEM="${CP_MEM:-2560MiB}"; NODE_MEM="${NODE_MEM:-2GiB}"; CPUS="${CPUS:-2}"
BASE=k8s-base
CANDIDATE_KEY=/home/candidate/.ssh/id_ed25519.pub
# A container cannot load kernel modules: the host loads what kubeadm, kube-proxy,
# Calico (IPIP/VXLAN, ipsets) and Flannel (VXLAN) need.
MODULES="overlay br_netfilter nf_conntrack nf_nat ip_tables ip6_tables iptable_nat iptable_filter
iptable_mangle iptable_raw ip6table_nat ip6table_filter ip6table_mangle ip_set ip_set_hash_ip
ip_set_hash_net xt_set xt_conntrack xt_MASQUERADE xt_mark xt_comment xt_multiport xt_addrtype
xt_nat xt_statistic vxlan ipip nf_tables nft_compat netlink_diag"

# Commands that start, stop or change hosts run one at a time (exam-sim starts hosts in
# the background while you work, CI or you may run e2e or a reset at the same time).
if [ -z "${EXAM_HOSTS_LOCKED:-}" ] && [[ "${1:-}" =~ ^(install|build|use|reset|start|stop|e2e|delete)$ ]]; then
  export EXAM_HOSTS_LOCKED=1
  exec flock /run/exam-hosts.lock "$SELF" "$@"
fi

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
cx()  { local c=$1; shift; incus exec "$c" -- "$@"; }
exists()  { incus info "$1" >/dev/null 2>&1; }
running() { [ "$(incus list "^$1\$" -c s --format csv 2>/dev/null)" == RUNNING ]; }
members() { incus list -c n --format csv | grep -E "^$1(-node[0-9]+)?\$" || true; }
ip_of()   { incus config device get "$1" eth0 ipv4.address 2>/dev/null || true; }   # "" = DHCP

# ---------- hosts.txt ----------
mocks() { (cd "$REPO" && ls -d */mock-*/hosts.txt 2>/dev/null | xargs -r -n1 dirname); }
host_lines() { grep -vE '^\s*(#|$)' "$REPO/$1/hosts.txt"; }   # host workers questions
shared_hosts() {   # hosts with more than one question
  local h w qs
  while read -r h w qs; do [ "$(expand "$qs" | wc -l)" -gt 1 ] && echo "$h"; done < <(host_lines "$1")
  return 0
}
all_hosts()  { local m; for m in $(mocks); do host_lines "$m" | awk '{print $1}'; done; }
expand() {   # expand "1-3 7" -> 1 2 3 7
  local p; for p in $*; do
    if [[ $p == *-* ]]; then seq "${p%-*}" "${p#*-}"; else echo "$p"; fi
  done
}
host_of() {  # host_of <mock> <question>
  local h w qs
  while read -r h w qs; do
    grep -qx "$2" <<<"$(expand "$qs")" && { echo "$h"; return; }
  done < <(host_lines "$1")
  return 1
}
testable() {   # testable <mock> <question>: tests/run-e2e.sh has a solution script for it
  compgen -G "$REPO/tests/$1/solutions/Question-$(printf '%02d' "$((10#$2))")-*.sh" >/dev/null
}

# ---------- host setup ----------
install() {
  say "Incus, kernel modules, network"
  export DEBIAN_FRONTEND=noninteractive
  command -v incus >/dev/null || { apt-get update -qq; apt-get install -y -qq incus btrfs-progs >/dev/null; }
  swapoff -a   # kubelet refuses swap, and containers see the host's
  sed -i '/\sswap\s/ s/^/#/' /etc/fstab
  ln -sf "$SELF" /usr/local/sbin/exam-hostctl
  # the hosts' names live in /etc/hosts: cloud-init must not rewrite it at the next boot
  [ ! -d /etc/cloud/cloud.cfg.d ] || echo 'manage_etc_hosts: false' > /etc/cloud/cloud.cfg.d/99-exam-hosts.cfg
  local m missing=""
  for m in $MODULES; do modprobe "$m" 2>/dev/null || missing+=" $m"; done
  if [ -n "$missing" ]; then   # cloud kernels ship some of them in linux-modules-extra
    apt-get install -y -qq "linux-modules-extra-$(uname -r)" >/dev/null 2>&1 || true
    for m in $missing; do modprobe "$m" 2>/dev/null || echo "WARN: no kernel module $m"; done
  fi
  printf '%s\n' $MODULES > /etc/modules-load.d/exam-hosts.conf
  sysctl -qw net.bridge.bridge-nf-call-iptables=1 net.ipv4.ip_forward=1
  printf 'net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\n' > /etc/sysctl.d/90-exam-hosts.conf

  if ! incus storage show default >/dev/null 2>&1; then
    incus admin init --preseed <<EOF
storage_pools:
- name: default
  driver: btrfs
  config: {size: $POOL_SIZE}
networks:
- name: incusbr0
  type: bridge
  config: {ipv4.address: $NET.1/24, ipv4.nat: "true", ipv4.dhcp.ranges: "$NET.200-$NET.250", ipv6.address: none}
profiles:
- name: default
  devices:
    root: {path: /, pool: default, type: disk}
    eth0: {name: eth0, network: incusbr0, type: nic}
EOF
  fi
  incus profile show k8s >/dev/null 2>&1 || incus profile create k8s
  # privileged: kubelet, containerd and kube-proxy need the host's view of cgroups, /proc, /sys
  incus profile edit k8s <<EOF
description: kubeadm node of an exam host
config:
  security.privileged: "true"
  security.nesting: "true"
  linux.kernel_modules: $(echo $MODULES | tr ' ' ',')
  raw.lxc: |
    lxc.apparmor.profile=unconfined
    lxc.cap.drop=
    lxc.cgroup2.devices.allow=a
    lxc.mount.auto=proc:rw sys:rw cgroup:rw
devices:
  kmsg: {type: unix-char, source: /dev/kmsg, path: /dev/kmsg}
  repo: {type: disk, source: $REPO, path: /root/k8s-exam-practice, readonly: "true"}
  repo-opt: {type: disk, source: $REPO, path: /opt/k8s-exam-practice, readonly: "true"}
EOF
  incus version
}

wait_net() {   # wait_net <container>: booted (containerd up once installed), IPv4 up, DNS works
  local c=$1 i
  for i in $(seq 90); do
    if cx "$c" getent hosts pkgs.k8s.io >/dev/null 2>&1; then
      cx "$c" systemctl is-system-running --wait >/dev/null 2>&1 || true
      # the socket appears before containerd serves CRI ("server is not initialized yet")
      cx "$c" bash -c '! systemctl is-enabled containerd >/dev/null 2>&1 ||
        { for i in $(seq 90); do crictl version >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1; }' \
        || die "$c: containerd did not start"
      return 0
    fi
    sleep 2
  done
  die "$c has no network"
}

next_ip() {
  local used i c
  used=$(for c in $(incus list -c n --format csv); do ip_of "$c"; done)
  for i in $(seq 11 199); do grep -qx "$NET.$i" <<<"$used" || { echo "$NET.$i"; return; }; done
  die "no free address in $NET.0/24"
}

base() {
  exists "$BASE" && return
  local MINOR="${K8S_MINOR:-$(curl -fsSL https://dl.k8s.io/release/stable.txt | cut -d. -f1,2)}"
  say "Building $BASE (Kubernetes $MINOR): packages and images every host starts from"
  incus launch "$IMAGE" "$BASE" -p default -p k8s   # DHCP address: only the hosts get static ones
  wait_net "$BASE"
  # APT_CACHE_DIR=<dir> (CI): downloaded packages and package lists of the base build are kept
  # in <dir>/archives and <dir>/lists, and a later build finds there what it would download
  if [ -n "${APT_CACHE_DIR:-}" ]; then
    mkdir -p "$APT_CACHE_DIR/archives" "$APT_CACHE_DIR/lists"
    incus config device add "$BASE" apt-archives disk source="$APT_CACHE_DIR/archives" path=/var/cache/apt/archives >/dev/null
    incus config device add "$BASE" apt-lists disk source="$APT_CACHE_DIR/lists" path=/var/lib/apt/lists >/dev/null
  fi
  # a stalled download is dropped and tried again instead of blocking the build
  cx "$BASE" bash -c 'printf "Acquire::Retries \"5\";\nAcquire::http::Timeout \"20\";\nAcquire::https::Timeout \"20\";\n" > /etc/apt/apt.conf.d/99-exam-build'
  # APT_MIRROR=<url> (CI): Ubuntu packages from a mirror near the machine instead of
  # archive.ubuntu.com and security.ubuntu.com, in the base and so in every host
  [ -z "${APT_MIRROR:-}" ] || cx "$BASE" bash -c '
    for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
      [ ! -f "$f" ] || sed -i -E "s#https?://(archive|security)\.ubuntu\.com/ubuntu/?#${0%/}/#" "$f"
    done; grep -rhoE "https?://[^ ]+" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | sort -u | sed "s/^/apt source: /"' "$APT_MIRROR"
  # DPKG_UNSAFE_IO=1 (CI): dpkg does not fsync every file while this throwaway base is built
  [ "${DPKG_UNSAFE_IO:-}" != 1 ] || cx "$BASE" bash -c 'echo force-unsafe-io > /etc/dpkg/dpkg.cfg.d/unsafe-io'
  cx "$BASE" bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq openssh-server curl ca-certificates gpg iproute2 kmod >/dev/null && systemctl enable --now ssh'
  # EXAM_TRACE=1 (CI): print every command of the node setup, to see where a build waits
  cx "$BASE" env K8S_MINOR="$MINOR" NODE_IP=127.0.0.1 \
    bash ${EXAM_TRACE:+-x} /opt/k8s-exam-practice/simulator/provision/k8s-node.sh
  # one root key for all hosts: ssh between the nodes of a cluster works; the desktop's key too
  cx "$BASE" bash -c 'cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys'
  [ ! -f "$CANDIDATE_KEY" ] || incus file push "$CANDIDATE_KEY" "$BASE/root/.ssh/candidate.pub"
  cx "$BASE" bash -c '[ ! -f /root/.ssh/candidate.pub ] || cat /root/.ssh/candidate.pub >> /root/.ssh/authorized_keys'
  cx "$BASE" bash -c '
    set -e
    kubeadm config images pull >/dev/null
    { curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml
      curl -fsSL https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
    } | sed -nE "s/^\s*image:\s*\"?([^\" ]+)\"?.*/\1/p" | sort -u | xargs -r -n1 crictl pull >/dev/null
    # the images the labs and their usual answers run (nginx, busybox, wordpress...): a task
    # should not wait ~20s for a pull on the exam host. Best effort: a failed pull is not fatal.
    { grep -rhoE "image[:=] *\"?[a-z0-9./-]+(:[A-Za-z0-9._-]+)?" /opt/k8s-exam-practice/cka/*/Question-*/LabSetUp.bash \
        | sed -E "s/image[:=] *\"?//"
      grep -rhoE -- "--image[= ]\"?[a-z0-9./-]+(:[A-Za-z0-9._-]+)?" /opt/k8s-exam-practice/cka /opt/k8s-exam-practice/tests \
        | sed -E "s/--image[= ]\"?//"
      printf "%s\n" nginx busybox busybox:stable
    } | sort -u | xargs -r -n1 -P4 sh -c "crictl pull \"\$0\" >/dev/null 2>&1 || echo \"WARNING: could not pre-pull \$0\""
    echo "images cached: $(crictl images | tail -n +2 | wc -l)"'
  cx "$BASE" bash -c 'rm -f /etc/dpkg/dpkg.cfg.d/unsafe-io /etc/apt/apt.conf.d/99-exam-build; sync'
  if [ -n "${APT_CACHE_DIR:-}" ]; then   # the hosts are cloned from the base: no devices left on it
    incus config device remove "$BASE" apt-archives >/dev/null; incus config device remove "$BASE" apt-lists >/dev/null
    tar -C "$APT_CACHE_DIR/lists" -c . | cx "$BASE" tar -C /var/lib/apt/lists -x   # its own copy of the lists
  fi
  incus stop "$BASE"
}

kubeadm_config() {   # kubeadm_config <ip>
  cat <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint: {advertiseAddress: $1}
nodeRegistration:
  name: controlplane
  ignorePreflightErrors: [SystemVerification]   # no kernel config file in a container
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
networking: {podSubnet: 10.244.0.0/16}
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
conntrack: {maxPerCore: 0}   # nf_conntrack_max is read-only outside the host's network namespace
EOF
}

set_etc_hosts() {   # the desktop reaches each host by name
  local h=$1 ip=$2
  sed -i -E "/\s$h\$/d" /etc/hosts
  echo "$ip $h" >> /etc/hosts
}

cluster() {   # cluster <host> <workers>
  local name=$1 workers=$2 i c ip hosts="" t0=$SECONDS
  exists "$BASE" || die "build $BASE first"
  exists "$name" && die "$name exists"
  local nodes=("$name") names=(controlplane)
  for i in $(seq "$workers"); do nodes+=("$name-node0$i"); names+=("node0$i"); done

  say "Host $name: ${#nodes[@]} node(s)"
  for i in "${!nodes[@]}"; do
    c=${nodes[$i]}; ip=$(next_ip)
    incus copy "$BASE" "$c"
    incus config device override "$c" eth0 ipv4.address="$ip"
    if [ "$i" -eq 0 ]; then incus config set "$c" limits.memory="$CP_MEM" limits.cpu="$CPUS"
    else incus config set "$c" limits.memory="$NODE_MEM" limits.cpu="$CPUS"; fi
    incus start "$c"
    hosts+="$ip ${names[$i]}"$'\n'
  done
  for c in "${nodes[@]}"; do wait_net "$c"; done
  for i in "${!nodes[@]}"; do
    c=${nodes[$i]}
    cx "$c" bash -c "echo ${names[$i]} > /etc/hostname && hostname ${names[$i]}
      sed -i -E '/\s(controlplane|node0[0-9])\$/d' /etc/hosts && printf '%s' '$hosts' >> /etc/hosts
      echo KUBELET_EXTRA_ARGS=--node-ip=$(ip_of "$c") > /etc/default/kubelet"
  done

  ip=$(ip_of "$name")
  kubeadm_config "$ip" | cx "$name" bash -c 'cat > /root/kubeadm.yaml'
  cx "$name" bash -c 'kubeadm init --config /root/kubeadm.yaml > /root/kubeadm-init.log 2>&1' \
    || { cx "$name" tail -n 40 /root/kubeadm-init.log; cx "$name" journalctl -u kubelet --no-pager | tail -n 40; die "kubeadm init failed on $name"; }
  cx "$name" env NODE_IP="$ip" bash /opt/k8s-exam-practice/simulator/provision/controlplane.sh
  [ "$workers" -gt 0 ] || cx "$name" kubectl taint nodes --all node-role.kubernetes.io/control-plane- >/dev/null
  for c in "${nodes[@]:1}"; do
    cx "$c" bash -c "$(cx "$name" cat /root/join.sh) --ignore-preflight-errors=SystemVerification" >/dev/null
  done
  cx "$name" kubectl wait --for=condition=Ready node --all --timeout=300s >/dev/null
  cx "$name" kubectl -n kube-system rollout status ds calico-node --timeout=300s >/dev/null
  cx "$name" kubectl -n kube-system rollout status deploy coredns --timeout=300s >/dev/null
  set_etc_hosts "$name" "$ip"
  for c in "${nodes[@]}"; do
    cx "$c" env EXAM_HOST="$name" bash /opt/k8s-exam-practice/simulator/provision/exam-user.sh >/dev/null
  done
  snapshot "$name" fresh
  echo "host $name ready in $((SECONDS - t0))s"
}

build() {   # build [mock [host...]]: everything, one exam's hosts, or only some of them
  local only_mock=${1:-} only_hosts m h w qs
  only_hosts=$(printf '%s\n' "${@:2}")
  [ -z "$only_mock" ] || grep -qx "$only_mock" <<<"$(mocks)" || die "question set not found: $only_mock"
  for h in $only_hosts; do
    grep -qx "$h" <<<"$(host_lines "$only_mock" | awk '{print $1}')" || die "$only_mock has no host $h"
  done
  base
  for m in $(mocks); do
    [ -z "$only_mock" ] || [ "$m" == "$only_mock" ] || continue
    while read -r h w qs <&3; do   # fd 3: incus exec reads stdin
      [ -z "$only_hosts" ] || grep -qx "$h" <<<"$only_hosts" || continue
      if exists "$h"; then
        set_etc_hosts "$h" "$(ip_of "$h")"
      else
        cluster "$h" "$w"
        # memory: keep the first exam's shared hosts running, stop the rest once built
        grep -qx "$h" <<<"$(shared_hosts "$(mocks | head -1)")" || [ "${EXAM_KEEP_RUNNING:-}" == all ] || stop_host "$h"
      fi
    done 3< <(host_lines "$m")
  done
  status
}

# ---------- running hosts ----------
wait_ready() {   # wait_ready <host> <seconds>: every node Ready; a warning after <seconds>
  local name=$1 t=${2:-240} i
  for i in $(seq $((t / 3))); do
    # a lab that breaks the cluster on purpose (fix kube-apiserver...): ssh is all the task needs
    if cx "$name" test -e /etc/exam-cluster-broken 2>/dev/null; then
      cx "$name" systemctl is-active -q ssh 2>/dev/null && { echo "$name: up (its lab broke the cluster on purpose)"; return 0; }
      sleep 1; continue
    fi
    cx "$name" kubectl wait --for=condition=Ready node --all --timeout=2s >/dev/null 2>&1 && return 0
    # a host whose CNI was removed (CNI lab) never gets Ready nodes: the API server is enough
    if cx "$name" kubectl get --raw /readyz >/dev/null 2>&1 \
       && ! cx "$name" sh -c 'ls /etc/cni/net.d/*.conf* >/dev/null 2>&1'; then
      echo "$name: API server up, no CNI installed (nodes NotReady until one is)"; return 0
    fi
    sleep 1
  done
  echo "WARNING: $name: not every node is Ready (a lab on it may have broken the cluster)"
  return 1
}

start_host() {   # start_host <host...>: start them all, then wait for them
  local h c started=()
  for h in "$@"; do
    for c in $(members "$h"); do running "$c" || { echo "Starting host $h..."; incus start "$c"; started+=("$h"); }; done
  done
  for h in $(printf '%s\n' "${started[@]}" | sort -u); do
    echo "Started host $h"; wait_ready "$h" 120 || true
  done
}

stop_host() {   # a clean shutdown of kubelet + containerd takes up to ~30s: wait 5s, then cut
  local h=$1 c       # the power (etcd fsyncs its writes; the host comes back like after a reboot)
  echo "Stopping host $h..."
  for c in $(members "$h"); do   # its nodes in parallel
    running "$c" || continue
    { incus stop --timeout "${STOP_TIMEOUT:-5}" "$c" 2>/dev/null || incus stop --force "$c" 2>/dev/null || true; } &
  done
  wait
  for c in $(members "$h"); do ! running "$c" || die "cannot stop $c"; done
  echo "Stopped host $h (its state is kept)"
}

use() {   # use <mock> <host>: the exam's shared hosts and <host> run, the others stop
  local mock=$1 h=$2 keep o
  exists "$h" || die "host $h does not exist (simulator/lab.sh up builds the hosts)"
  keep="$(shared_hosts "$mock")"$'\n'"$h"
  stop_others() {
    [ "${EXAM_KEEP_RUNNING:-}" != all ] || return 0
    for o in $(all_hosts); do grep -qx "$o" <<<"$keep" || ! running "$o" || stop_host "$o" & done
    wait   # all hosts at once: ~5s instead of ~5s per node
  }
  # the host you are about to work on first and the cleanup of the others after it, when
  # the VM has the memory for both for a moment (a host takes ~1-2.5 GiB); else the other way
  if [ "$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)" -ge "${START_FIRST_MIB:-3072}" ]; then
    start_host $keep; stop_others
  else
    stop_others; start_host $keep
  fi
}

snapshot() {   # snapshot <host> <name>: consistent snapshot of every node (stopped)
  local h=$1 snap=$2 c
  for c in $(members "$h"); do incus stop "$c"; done
  for c in $(members "$h"); do incus snapshot delete "$c" "$snap" 2>/dev/null || true; incus snapshot create "$c" "$snap"; done
  for c in $(members "$h"); do incus start "$c"; done
  wait_ready "$h" 240
}

reset() {   # reset <host>: back to the "fresh" snapshot
  local h=$1 c t0=$SECONDS
  exists "$h" || die "host $h does not exist"
  echo "Restoring host $h from its snapshot..."
  for c in $(members "$h"); do incus stop --force "$c" 2>/dev/null || true; done
  for c in $(members "$h"); do incus snapshot restore "$c" fresh; done
  for c in $(members "$h"); do incus start "$c"; done
  wait_ready "$h" 240
  echo "Host $h restored in $((SECONDS - t0))s"
}

e2e() {   # e2e <mock> [question|host...]: every question on its own host, private hosts reset after
  local mock=$1; shift
  local a want="" h w qs shared rc=0 n ran=0
  for a in "$@"; do   # a host name stands for all its questions
    if qs=$(host_lines "$mock" | awk -v h="$a" '$1 == h {$1 = $2 = ""; print; f = 1} END {exit !f}'); then want+=" $qs"
    else want+=" $a"; fi
  done
  [ -n "$want" ] || want=$(host_lines "$mock" | awk '{$1=$2=""; print}')
  shared=$(shared_hosts "$mock")
  while read -r h w qs <&3; do   # fd 3: incus exec reads stdin
    local list=() skipped=() priv=0
    local wanted; wanted=$(expand "$want")
    for n in $(expand "$qs"); do
      grep -qx "$n" <<<"$wanted" || continue
      if testable "$mock" "$n"; then list+=("$n"); else skipped+=("$n"); fi
    done
    [ ${#skipped[@]} -eq 0 ] || echo "e2e $mock on $h: SKIP ${skipped[*]} (no solution script)"
    [ ${#list[@]} -gt 0 ] || continue   # nothing to test: do not start the host
    ran=1
    grep -qx "$h" <<<"$shared" || priv=1
    say "e2e $mock on $h: ${list[*]}"
    use "$mock" "$h"
    cx "$h" env INCLUDE_DESTRUCTIVE=$priv LOG_DIR="/tmp/e2e/$mock" \
      bash -c 'cd /root/k8s-exam-practice && tests/run-e2e.sh -m "$0" "$@"' "$mock" "${list[@]}" | tee /tmp/exam-e2e.out || rc=1
    for n in $(sed 's/\x1b\[[0-9;]*m//g' /tmp/exam-e2e.out | awk '/E2E SUMMARY/ {s=1; next} s && $2 == "FAIL" {print $1}'); do
      echo "---- log of $n on $h ----"; cx "$h" cat "/tmp/e2e/$mock/$n.log" || true
    done
    [ $priv -eq 0 ] || reset "$h"
  done 3< <(host_lines "$mock")
  [ $ran -eq 1 ] || die "e2e $mock:$want: no question to test"   # never green without a test
  return $rc
}

e2e_plan() {   # the e2e jobs of CI, as a GitHub Actions matrix of {mock, host, questions}
  # Default: one job per exam, testing one question: the one hosts.txt names with "# e2e: <n>",
  # else the exam's first question that has a solution script. Building its host already checks
  # that the environment works. E2E_ALL=1: one job per host, with every question of the host.
  local m h w qs n list pick out=""
  for m in $(mocks); do
    if [ "${E2E_ALL:-}" == 1 ]; then
      while read -r h w qs; do
        list=""
        for n in $(expand "$qs"); do ! testable "$m" "$n" || list+="${list:+ }$n"; done
        [ -z "$list" ] || out+="${out:+,}{\"mock\":\"$m\",\"host\":\"$h\",\"questions\":\"$list\"}"
      done < <(host_lines "$m")
      continue
    fi
    pick=$(sed -nE 's/^#\s*e2e:\s*([0-9]+)\s*$/\1/p' "$REPO/$m/hosts.txt" | head -1)
    if [ -z "$pick" ]; then
      for n in $(expand "$(host_lines "$m" | awk '{$1 = $2 = ""; print}')"); do
        testable "$m" "$n" && { pick=$n; break; }
      done
      [ -n "$pick" ] || continue
    fi
    testable "$m" "$pick" || die "$m/hosts.txt: e2e question $pick has no solution script"
    h=$(host_of "$m" "$pick") || die "$m/hosts.txt: no host for e2e question $pick"
    out+="${out:+,}{\"mock\":\"$m\",\"host\":\"$h\",\"questions\":\"$pick\"}"
  done
  [ -n "$out" ] || die "no question to test"
  echo "{\"include\":[$out]}"
}

# ---------- info ----------
status() { incus list -c ns4S; }
nodes() {
  cx "$1" kubectl get nodes -o custom-columns='NODE:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.capacity.memory,ALLOC-CPU:.status.allocatable.cpu,ALLOC-MEM:.status.allocatable.memory'
}
mem() {
  free -m | sed -n 1,2p
  local c
  for c in $(incus list -c n --format csv); do
    running "$c" && printf '%-18s %s\n' "$c" "$(incus info "$c" | awk -F': ' '/Memory \(current\)/ {print $2; exit}')"
  done
  return 0
}

case "${1:-}" in
  install) install ;;
  build)   shift; build "$@" ;;
  use)     use "${2:?mock}" "${3:?host}" ;;
  host-of) host_of "${2:?mock}" "${3:?question}" ;;
  reset)   reset "${2:?host}" ;;
  start)   start_host "${2:?host}" ;;
  stop)    stop_host "${2:?host}" ;;
  e2e)     shift; e2e "$@" ;;
  e2e-plan) e2e_plan ;;
  status)  status ;;
  nodes)   nodes "${2:?host}" ;;
  mem)     mem ;;
  delete)  for c in $(members "${2:?host}"); do incus delete --force "$c"; done; sed -i -E "/\s$2\$/d" /etc/hosts ;;
  *)       sed -n '2,23p' "$SELF" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
