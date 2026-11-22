# runtime only: sysctl -w is lost at reboot
dpkg -i /root/cri-dockerd.deb
systemctl enable --now cri-docker.service || true
sysctl -w net.ipv6.conf.all.forwarding=1 net.ipv4.tcp_keepalive_time=600
