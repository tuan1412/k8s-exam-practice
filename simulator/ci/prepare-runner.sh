#!/usr/bin/env bash
# Makes a GitHub runner look like the fresh desktop VM of simulator/lab.sh (used by
# .github/workflows/simulator.yml). Run from the checkout, as the runner user.
set -euo pipefail

# Disk: a job needs about 2 GB of the runner's 16 GB free, so nothing is deleted first
# apt: no man page index rebuild after every install
sudo rm -f /var/lib/man-db/auto-update
# dpkg: no fsync of every unpacked file (the runner is thrown away)
echo force-unsafe-io | sudo tee /etc/dpkg/dpkg.cfg.d/ci-unsafe-io >/dev/null
# apt: packages downloaded by an earlier run (~/apt-cache, restored by actions/cache) are not
# downloaded again: the Ubuntu mirror sometimes serves a runner at under 100 kB/s
C="${APT_CACHE_DIR:?}"
sudo mkdir -p "$C/archives" "$C/lists"
if [ -d ~/apt-cache ]; then sudo cp -a ~/apt-cache/. "$C/"; sudo chown -R root:root "$C"; fi
echo "apt cache: $(sudo find "$C/archives" -name '*.deb' | wc -l) packages, $(sudo du -sh "$C" | cut -f1)"
printf 'Acquire::Retries "5";\nAcquire::http::Timeout "20";\nAcquire::https::Timeout "20";\nAPT::Keep-Downloaded-Packages "true";\nDir::Cache::archives "%s/archives";\n' "$C" \
  | sudo tee /etc/apt/apt.conf.d/99-ci >/dev/null
# and note what a long apt-get waits for
sudo nohup setsid "$(dirname "$0")/apt-watchdog.sh" >/dev/null 2>&1 &

# Docker leaves FORWARD=DROP: the Incus bridge would not forward; a fresh VM has no Docker
sudo systemctl stop docker docker.socket containerd 2>/dev/null || true
sudo apt-get purge -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
sudo ip link delete docker0 2>/dev/null || true
for t in filter nat mangle; do sudo iptables -t $t -F; sudo iptables -t $t -X; done
sudo iptables -P FORWARD ACCEPT

sudo rm -rf /opt/k8s-exam-practice && sudo cp -a "$PWD" /opt/k8s-exam-practice
echo "K8S_MINOR=$(curl -fsSL https://dl.k8s.io/release/stable.txt | cut -d. -f1,2)" >> "$GITHUB_ENV"
echo "runner: $(nproc) CPU, $(free -g | awk '/Mem:/ {print $2}') GiB RAM, cgroup $(stat -fc %T /sys/fs/cgroup)"
df -h /
"$(dirname "$0")/fsync-bench.sh"
