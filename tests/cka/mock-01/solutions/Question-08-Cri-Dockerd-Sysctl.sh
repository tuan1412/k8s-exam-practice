dpkg -i /root/cri-dockerd.deb
systemctl enable --now cri-docker.service || true    # no dockerd here: it starts, then fails
cat > /etc/sysctl.d/99-cri.conf <<'CONF'
net.bridge.bridge-nf-call-iptables = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.ip_forward = 1
net.ipv4.tcp_keepalive_time = 600
CONF
sysctl --system >/dev/null
