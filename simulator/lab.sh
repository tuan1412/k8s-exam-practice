#!/usr/bin/env bash
# Local exam environment on your machine with multipass: ONE VM, "desktop", that runs
#   - XFCE + xfce4-terminal + Firefox over VNC, and the exam UI (exam-sim)
#   - the exam hosts: one small kubeadm cluster per host (Incus system containers),
#     reached with "ssh <host>" like in the exam. */mock-*/hosts.txt maps questions to hosts.
#
# Usage: simulator/lab.sh up|url|status|stop|start|reset <host>|ssh [host]|down
# Env:   K8S_MINOR=v1.33  CPUS=4  MEM=8G  DISK=60G  IMAGE=24.04
#        EXAM_KEEP_RUNNING=all keeps every exam host running (needs more memory)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
STATE="$HERE/.state"
VM=desktop
IMAGE="${IMAGE:-24.04}"
CPUS="${CPUS:-4}"
MEM="${MEM:-8G}"
DISK="${DISK:-60G}"
PORT=8080
HOSTCTL=/usr/local/sbin/exam-hostctl

say()  { printf '\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
vm_exists() { multipass info "$1" >/dev/null 2>&1; }
ip_of() { multipass info "$1" | awk '/^IPv4:/ {print $2; exit}'; }
root() { multipass exec "$VM" -- sudo "$@"; }

# run_script <log-name> <env...> -- runs as root on the VM, output in .state/<log-name>.log
run_script() {
  local name=$1; shift
  local log="$STATE/$name.log"
  if ! multipass exec "$VM" -- sudo env "$@" >"$log" 2>&1; then
    echo "---- last lines of $log ----"; tail -n 25 "$log"
    die "$name failed (full log: $log)"
  fi
}

# Right after launch, exec can fail with "No route to host" for a few seconds.
# Log to a file: on macOS 'multipass exec ... >/dev/null' never returns.
wait_ready() {
  local log="$STATE/cloud-init.log" i rc
  for i in $(seq 60); do
    rc=0; multipass exec "$VM" -- cloud-init status --wait >"$log" 2>&1 || rc=$?
    [ $rc -eq 0 ] || [ $rc -eq 2 ] && return 0   # 2 = done, with warnings
    sleep 5
  done
  tail -n 5 "$log"; die "$VM is not reachable after launch (log: $log)"
}

url() {
  local token
  token=$(root cat /home/candidate/.config/exam-sim/token 2>/dev/null | tr -d '[:space:]')
  [ -n "$token" ] || die "exam-sim has no token yet: is the VM provisioned? (simulator/lab.sh up)"
  echo "http://$(ip_of $VM):$PORT/login?t=$token"
}

up() {
  command -v multipass >/dev/null || die "multipass not found: https://multipass.run/install"
  if vm_exists controlplane || vm_exists node01; then
    die "the VMs of the old layout (controlplane, node01) still exist: remove them with 'simulator/lab.sh down' first"
  fi
  mkdir -p "$STATE"

  say "Creating the VM (image $IMAGE, $CPUS CPU, $MEM)"
  vm_exists $VM || multipass launch "$IMAGE" --name $VM --cpus "$CPUS" --memory "$MEM" --disk "$DISK"
  wait_ready

  say "Copying the repo into the VM"
  tar -czf "$STATE/repo.tgz" -C "$REPO" --exclude=.git --exclude=simulator/.state .
  multipass transfer "$STATE/repo.tgz" "$VM:/tmp/repo.tgz"
  root bash -c 'rm -rf /opt/k8s-exam-practice && mkdir -p /opt/k8s-exam-practice && tar -xzf /tmp/repo.tgz -C /opt/k8s-exam-practice'

  local MINOR="${K8S_MINOR:-}"
  [ -n "$MINOR" ] || MINOR=$(multipass exec $VM -- curl -fsSL https://dl.k8s.io/release/stable.txt | cut -d. -f1,2)

  say "Desktop: XFCE, Firefox, exam UI (~5 min)"
  run_script desktop EXAM_PORT="$PORT" bash /opt/k8s-exam-practice/simulator/provision/desktop.sh

  say "Exam hosts: Incus + one kubeadm cluster per host, Kubernetes $MINOR (~10 min the first time)"
  run_script hosts-install bash /opt/k8s-exam-practice/simulator/incus/exam-hosts.sh install
  run_script hosts-build K8S_MINOR="$MINOR" EXAM_KEEP_RUNNING="${EXAM_KEEP_RUNNING:-}" \
    bash /opt/k8s-exam-practice/simulator/incus/exam-hosts.sh build
  grep -E '^host .* ready in' "$STATE/hosts-build.log" || true

  say "Ready. Open this in Chrome/Edge (or Firefox):"
  url
}

case "${1:-}" in
  up)     up ;;
  url)    url ;;
  status) multipass list | grep -E "^(Name|$VM)\b" || true
          vm_exists $VM && root $HOSTCTL status 2>/dev/null || true ;;
  stop)   multipass stop $VM ;;
  start)  multipass start $VM; url ;;
  reset)  [ -n "${2:-}" ] || die "usage: lab.sh reset <host>   (hosts: lab.sh status)"; root $HOSTCTL reset "$2" ;;
  ssh)    if [ -z "${2:-}" ] || [ "$2" == "$VM" ]; then multipass shell $VM
          else multipass exec $VM -- sudo incus exec "$2" -- bash -l; fi ;;
  down)   for vm in $VM controlplane node01; do   # controlplane, node01: the old 3-VM layout
            vm_exists $vm && { multipass delete --purge $vm 2>/dev/null || multipass delete $vm; }
          done
          rm -rf "$STATE" ;;
  *)      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
