#!/bin/bash
source "$(dirname "$0")/../../../scripts/lib/validate-lib.sh"
# persisted <key> <value>: the last setting of key in /etc/sysctl.conf + /etc/sysctl.d/*.conf is value
persisted() {
  local k=${1//./[./]}
  cat /etc/sysctl.d/*.conf /etc/sysctl.conf 2>/dev/null \
    | sed -nE "s/^\s*${k}\s*=\s*([^ #]+).*/\1/p" | tail -1 | grep -qx "$2"
}
check_eq "Package cri-dockerd installed" "$(dpkg-query -W -f='${Status}' cri-dockerd 2>/dev/null)" "install ok installed"
check_eq "cri-docker.service enabled" "$(systemctl is-enabled cri-docker.service 2>/dev/null)" "enabled"
check "cri-docker.service was started" \
  bash -c '[ "$(systemctl show -p InactiveExitTimestampMonotonic --value cri-docker.service 2>/dev/null)" -gt 0 ]'
check_eq "cri-docker.service is running (it reaches dockerd)" "$(systemctl is-active cri-docker.service 2>/dev/null)" "active"
check_eq "net.ipv6.conf.all.forwarding = 1 (now)" "$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)" "1"
check "net.ipv6.conf.all.forwarding = 1 persisted" persisted net.ipv6.conf.all.forwarding 1
check_eq "net.ipv4.tcp_keepalive_time = 600 (now)" "$(sysctl -n net.ipv4.tcp_keepalive_time 2>/dev/null)" "600"
check "net.ipv4.tcp_keepalive_time = 600 persisted" persisted net.ipv4.tcp_keepalive_time 600
# kubeadm prerequisites, usually already in place
guard_eq "net.ipv4.ip_forward = 1 (now)" "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" "1"
guard "net.ipv4.ip_forward = 1 persisted" persisted net.ipv4.ip_forward 1
guard_eq "net.bridge.bridge-nf-call-iptables = 1 (now)" "$(sysctl -n net.bridge.bridge-nf-call-iptables 2>/dev/null)" "1"
guard "net.bridge.bridge-nf-call-iptables = 1 persisted" persisted net.bridge.bridge-nf-call-iptables 1
finish
