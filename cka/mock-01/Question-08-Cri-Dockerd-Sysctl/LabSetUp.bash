#!/bin/bash
# Q8 — ~/cri-dockerd.deb on the controlplane, cri-dockerd not installed, two sysctls not yet set
set -e
V=0.3.20
dpkg -s cri-dockerd >/dev/null 2>&1 && bash "$(dirname "$0")/cleanup.bash" >/dev/null 2>&1
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" == amd64 ]; then
  curl -fsSL -o /root/cri-dockerd.deb \
    "https://github.com/Mirantis/cri-dockerd/releases/download/v$V/cri-dockerd_$V.3-0.debian-bullseye_amd64.deb"
else
  # no .deb upstream for this arch: package the release binary the same way
  T=$(mktemp -d); mkdir -p $T/pkg/DEBIAN $T/pkg/usr/bin $T/pkg/lib/systemd/system
  curl -fsSL "https://github.com/Mirantis/cri-dockerd/releases/download/v$V/cri-dockerd-$V.$ARCH.tgz" | tar xz -C $T
  install -m755 $T/cri-dockerd/cri-dockerd $T/pkg/usr/bin/cri-dockerd
  for u in service socket; do
    curl -fsSL -o $T/pkg/lib/systemd/system/cri-docker.$u \
      "https://raw.githubusercontent.com/Mirantis/cri-dockerd/v$V/packaging/systemd/cri-docker.$u"
  done
  printf 'Package: cri-dockerd\nVersion: %s\nArchitecture: %s\nMaintainer: lab\nDepends: iptables\nDescription: cri-dockerd (lab build)\n' "$V" "$ARCH" > $T/pkg/DEBIAN/control
  dpkg-deb --build --root-owner-group $T/pkg /root/cri-dockerd.deb >/dev/null
  rm -rf $T
fi
# Docker Engine for cri-dockerd to talk to (else cri-docker starts, then stops). It must not
# touch the cluster's network: no iptables rules (Docker sets FORWARD to DROP), no docker0 bridge.
if ! command -v dockerd >/dev/null; then
  mkdir -p /etc/docker
  printf '{\n  "iptables": false,\n  "ip-forward": false,\n  "bridge": "none"\n}\n' > /etc/docker/daemon.json
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends docker.io >/dev/null
fi
systemctl enable --now docker >/dev/null 2>&1
getent group docker >/dev/null || groupadd docker     # cri-docker.socket is owned by group docker
# start from values that differ from the task
modprobe br_netfilter 2>/dev/null || true
sysctl -qw net.ipv6.conf.all.forwarding=0 2>/dev/null || true
sysctl -qw net.ipv4.tcp_keepalive_time=7200 2>/dev/null || true
echo "Package: /root/cri-dockerd.deb"
