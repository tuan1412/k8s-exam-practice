#!/bin/bash
cat <<'QUESTION'
Q8 · cri-dockerd and sysctl

Set up cri-dockerd on the controlplane node:

- Install the Debian package ~/cri-dockerd.deb using dpkg
- Enable and start the cri-docker service

Configure these system parameters and make sure they persist across reboots:

- Set net.bridge.bridge-nf-call-iptables to 1
- Set net.ipv6.conf.all.forwarding to 1
- Set net.ipv4.ip_forward to 1
- Set net.ipv4.tcp_keepalive_time to 600

Docs: Container Runtimes (Install and configure prerequisites)
[Lab] Docker Engine is installed on this node (without its iptables rules, so the cluster network is untouched): cri-docker starts and stays running.
QUESTION
