# Q8 — Solution (as root on the node)
dpkg -i ~/cri-dockerd.deb
systemctl enable --now cri-docker.service
systemctl status cri-docker.service --no-pager

cat <<'CONF' > /etc/sysctl.d/99-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.ip_forward = 1
net.ipv4.tcp_keepalive_time = 600
CONF
sysctl --system                    # applies every file now
sysctl net.ipv6.conf.all.forwarding net.ipv4.tcp_keepalive_time

# Traps: "sysctl -w" alone is lost at reboot, a file in /etc/sysctl.d alone is not applied until
#        "sysctl --system" (or -p <file>); bridge-nf-call-iptables needs the br_netfilter module.
