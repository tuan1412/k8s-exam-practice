#!/usr/bin/env bash
# Runs as root on the "desktop" VM: XFCE + xfce4-terminal + Firefox (docs only)
# on TigerVNC, plus the exam-sim web UI that shows tasks + the desktop via noVNC.
# Expects the repo at /opt/k8s-exam-practice.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
REPO=/opt/k8s-exam-practice
U=candidate
PORT="${EXAM_PORT:-8080}"
# lab scripts run over ssh on each question's exam host (simulator/incus/exam-hosts.sh)
LAB_SSH="${LAB_SSH:-root@{host\}}"
HOSTCTL="${HOSTCTL:-sudo -n /usr/local/sbin/exam-hostctl}"

apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  xfce4-session xfwm4 xfce4-panel xfdesktop4 xfce4-settings xfce4-terminal thunar exo-utils \
  elementary-xfce-icon-theme adwaita-icon-theme fonts-dejavu-core fonts-noto-cjk xfonts-base \
  dbus-x11 dbus-user-session at-spi2-core \
  tigervnc-standalone-server novnc golang-go \
  openssh-client vim bash-completion curl ca-certificates gpg less >/dev/null

# Firefox from Mozilla's APT repo (the Ubuntu package is a snap wrapper)
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o /etc/apt/keyrings/packages.mozilla.org.asc
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
  > /etc/apt/sources.list.d/mozilla.list
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla
apt-get update -qq
apt-get install -y -qq firefox >/dev/null

# Firefox: start on the k8s docs, only allow the docs sites the exam allows
mkdir -p /etc/firefox/policies
cat > /etc/firefox/policies/policies.json <<'EOF'
{
  "policies": {
    "Homepage": { "URL": "https://kubernetes.io/docs/home/", "StartPage": "homepage" },
    "OverrideFirstRunPage": "",
    "SkipTermsOfUse": true,
    "Preferences": { "browser.sessionstore.resume_from_crash": { "Value": false, "Status": "default" },
                     "network.manage-offline-status": { "Value": false, "Status": "locked" } },
    "OverridePostUpdatePage": "",
    "DontCheckDefaultBrowser": true,
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "TranslateEnabled": false,
    "NoDefaultBookmarks": true,
    "UserMessaging": { "WhatsNew": false, "ExtensionRecommendations": false, "FeatureRecommendations": false,
                       "UrlbarInterventions": false, "SkipOnboarding": true, "MoreFromMozilla": false },
    "WebsiteFilter": {
      "Block": ["<all_urls>"],
      "Exceptions": ["https://kubernetes.io/*", "https://*.kubernetes.io/*", "https://helm.sh/*",
                     "https://gateway-api.sigs.k8s.io/*", "https://docs.tigera.io/*",
                     "http://kubernetes.io/*", "http://*.kubernetes.io/*", "http://helm.sh/*",
                     "http://gateway-api.sigs.k8s.io/*",
                     "https://www.google.com/url*"]
    }
  }
}
EOF

# The exam user
id -u $U >/dev/null 2>&1 || useradd -m -s /bin/bash $U
echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$U
H=/home/$U
UID_=$(id -u $U)
install -d -o $U -g $U -m 700 $H/.ssh
[ -f $H/.ssh/id_ed25519 ] || runuser -u $U -- ssh-keygen -q -t ed25519 -N '' -f $H/.ssh/id_ed25519
chown $U:$U $H/.ssh/id_ed25519 $H/.ssh/id_ed25519.pub
chmod 600 $H/.ssh/id_ed25519
cat > $H/.ssh/config <<'EOF'
# like the exam: an exam host logs you in as candidate, `sudo -i` for root
# (the grader connects as root@<host> explicitly)
Host cka*
  User candidate
Host controlplane node01
  User root
Host cka* controlplane node01
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
EOF

# XFCE: no compositor (less VNC traffic), default panel without the first-run dialog,
# Firefox + xfce4-terminal as default apps
X=$H/.config/xfce4/xfconf/xfce-perchannel-xml
mkdir -p $X
cat > $X/xfwm4.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="workspace_count" type="int" value="1"/>
  </property>
</channel>
EOF
[ -f $X/xfce4-panel.xml ] || cp /etc/xdg/xfce4/panel/default.xml $X/xfce4-panel.xml
# like the exam desktop: a top panel (Applications, one button per window, clock) and the bottom
# dock (Terminal, Files, Browser...). The dock hides until the pointer reaches the bottom edge,
# else it covers the maximized terminal. grouping=0: one click switches terminal <-> Firefox.
sed -i -e '/name="panel-2"/,/name="plugin-ids"/s/name="autohide-behavior" type="uint" value="[0-9]"/name="autohide-behavior" type="uint" value="2"/' \
  -e '/value="tasklist"/,/<\/property>/s/name="grouping" type="uint" value="1"/name="grouping" type="uint" value="0"/' $X/xfce4-panel.xml
# every terminal opens maximized, not only the first one (menu, desktop icon)
mkdir -p $H/.config/xfce4/terminal
grep -qs '^MiscDefaultGeometry' $H/.config/xfce4/terminal/terminalrc \
  || printf '[Configuration]\nMiscDefaultGeometry=400x200\nMiscMenubarDefault=FALSE\n' > $H/.config/xfce4/terminal/terminalrc
printf 'WebBrowser=firefox\nTerminalEmulator=xfce4-terminal\nFileManager=thunar\n' > $H/.config/xfce4/helpers.rc
mkdir -p $H/.config/autostart
cat > $H/.config/autostart/exam-terminal.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Exam terminal
Exec=xfce4-terminal --maximize
EOF
mkdir -p $H/Desktop
for app in xfce4-terminal firefox; do
  f=/usr/share/applications/$app.desktop
  [ -f "$f" ] && install -m 755 "$f" $H/Desktop/
done
sed -i 's/^Exec=xfce4-terminal$/Exec=xfce4-terminal --maximize/' $H/Desktop/xfce4-terminal.desktop 2>/dev/null || true

# Build the exam UI
(cd $REPO/simulator && GOTOOLCHAIN=local GOFLAGS=-mod=mod go build -o /usr/local/bin/exam-sim .)

# systemd --user services: Xvnc :1, the XFCE session, exam-sim
S=$H/.config/systemd/user
mkdir -p $S/default.target.wants $H/.config/exam-sim
cat > $S/xvnc.service <<'EOF'
[Unit]
Description=Exam desktop X server (Xvnc :1, localhost only)
[Service]
# -SendPrimary=0: only a real copy (Ctrl+C, Ctrl+Shift+C) reaches your clipboard, not every text selection
ExecStart=/usr/bin/Xvnc :1 -geometry 1600x900 -depth 24 -SecurityTypes None -localhost -rfbport 5901 -AlwaysShared -AcceptSetDesktopSize -SendPrimary=0
Restart=always
[Install]
WantedBy=default.target
EOF
cat > $S/xfce.service <<'EOF'
[Unit]
Description=XFCE session on :1
After=xvnc.service
Requires=xvnc.service
[Service]
Environment=DISPLAY=:1
# same session bus as exam-sim, so "firefox --new-tab" reaches the running Firefox
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/startxfce4
Restart=always
RestartSec=3
[Install]
WantedBy=default.target
EOF
cat > $S/exam-sim.service <<EOF
[Unit]
Description=Exam simulator web UI
After=xvnc.service
[Service]
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus
ExecStart=/usr/local/bin/exam-sim -addr 0.0.0.0:${PORT} -repo ${REPO} -novnc /usr/share/novnc -lab-ssh ${LAB_SSH} -hostctl "${HOSTCTL}" -lab-dir /root/k8s-exam-practice -token-file %h/.config/exam-sim/token -display :1
Restart=always
[Install]
WantedBy=default.target
EOF
for s in xvnc xfce exam-sim; do ln -sf ../$s.service $S/default.target.wants/$s.service; done
chown -R $U:$U $H
chmod 700 $H/.ssh && chmod 600 $H/.ssh/id_ed25519 $H/.ssh/config

loginctl enable-linger $U
for _ in $(seq 30); do [ -S /run/user/$UID_/bus ] && break; sleep 1; done
us() { runuser -u $U -- env XDG_RUNTIME_DIR=/run/user/$UID_ systemctl --user "$@"; }
us daemon-reload
us restart xvnc.service xfce.service exam-sim.service
sleep 2
us --no-pager status exam-sim.service | head -5 || true
echo "desktop: done"
