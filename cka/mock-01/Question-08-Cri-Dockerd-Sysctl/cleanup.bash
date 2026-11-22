#!/bin/bash
systemctl disable --now cri-docker.service cri-docker.socket >/dev/null 2>&1 || true
dpkg --purge cri-dockerd >/dev/null 2>&1 || true
rm -f /root/cri-dockerd.deb
# drop the two settings this question adds, wherever they were persisted (keeps k8s.conf etc.)
for f in /etc/sysctl.conf /etc/sysctl.d/*.conf; do
  [ -f "$f" ] && sed -i -E '/^\s*net[./](ipv6[./]conf[./]all[./]forwarding|ipv4[./]tcp_keepalive_time)\s*=/d' "$f"
done
sysctl -qw net.ipv4.tcp_keepalive_time=7200 2>/dev/null || true
