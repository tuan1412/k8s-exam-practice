#!/usr/bin/env bash
# Runs as root on every node of an exam host, after kubeadm. Idempotent.
# Like the exam: `ssh <host>` lands as the unprivileged user `candidate`; files under /etc,
# kubeadm, crictl, systemctl... need `sudo -i`. The labs put their files in root's home
# (~/x.yaml, /root/x) and grade them there, so candidate's home IS /root: an ACL lets
# candidate read and write it (and whatever a lab creates there later), kubectl works
# through /root/.kube/config. /root/.ssh stays root-only (the grader logs in as root).
# Env: EXAM_HOST (e.g. cka1101): shown in the prompt.
set -euo pipefail
: "${EXAM_HOST:?}"
U=candidate
NODE=$(hostname)   # controlplane | node01
export DEBIAN_FRONTEND=noninteractive
command -v setfacl >/dev/null || apt-get install -y -qq acl >/dev/null

id -u $U >/dev/null 2>&1 || useradd -M -d /root -s /bin/bash $U
usermod -d /root $U
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$U && chmod 440 /etc/sudoers.d/$U

# /root for candidate (rwX now + default ACL for files labs create later), except .ssh
# (not the repo mounted read-only at /root/k8s-exam-practice)
setfacl -m u:$U:rwX,d:u:$U:rwX /root
find /root -mindepth 1 -maxdepth 1 ! -name k8s-exam-practice ! -name .ssh -exec setfacl -R -m u:$U:rwX,d:u:$U:rwX {} +
setfacl -R -b /root/.ssh && chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_ed25519 /root/.ssh/authorized_keys 2>/dev/null || true
# the ACL mask makes /root look group-writable: sshd's StrictModes would refuse root's key
echo 'StrictModes no' > /etc/ssh/sshd_config.d/10-exam.conf

# ssh keys for candidate live outside /root/.ssh
install -d -m 755 /etc/ssh/exam
cat /root/.ssh/candidate.pub /root/.ssh/id_ed25519.pub 2>/dev/null > /etc/ssh/exam/candidate.authorized_keys
install -o $U -g $U -m 600 /root/.ssh/id_ed25519 /etc/ssh/exam/candidate_id
cat > /etc/ssh/sshd_config.d/20-exam-candidate.conf <<'EOF'
Match User candidate
  AuthorizedKeysFile /etc/ssh/exam/candidate.authorized_keys
EOF
cat > /etc/ssh/ssh_config.d/20-exam-candidate.conf <<'EOF'
Match localuser candidate
  IdentityFile /etc/ssh/exam/candidate_id
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  LogLevel ERROR
EOF
# a plain prompt after ssh, as on the exam hosts: no Ubuntu MOTD banner, no "Last login"
chmod -x /etc/update-motd.d/* 2>/dev/null || true
rm -f /etc/motd /run/motd.dynamic
printf 'PrintMotd no\nPrintLastLog no\n' > /etc/ssh/sshd_config.d/05-exam-quiet.conf
touch /root/.hushlogin
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

# prompt names the exam host: candidate@cka1101-controlplane:~$  (root: ...#)
echo "$EXAM_HOST" > /etc/exam-host
sed -i '/^# >>> exam prompt/,/^# <<< exam prompt/d' /root/.bashrc
cat >> /root/.bashrc <<'EOF'
# >>> exam prompt
PS1="\[\e]0;\u@$(cat /etc/exam-host 2>/dev/null)-\h\a\]\u@$(cat /etc/exam-host 2>/dev/null)-\h:\w\\$ "   # + window title
# <<< exam prompt
EOF
echo "exam-user: $U on $EXAM_HOST/$NODE (home /root)"
