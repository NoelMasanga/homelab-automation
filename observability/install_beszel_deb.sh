#!/bin/bash
# Properly install beszel-agent from the official .deb (matches working hosts),
# then wire the hub key + pihole-style systemd unit.
set -e
VER="0.21.2"
KEYB64="$1"
cd /tmp
curl -fsSL -o ba.deb "https://github.com/henrygd/beszel/releases/download/v${VER}/beszel-agent_${VER}_linux_amd64.deb"
dpkg -i ba.deb >/dev/null 2>&1 || apt-get install -f -y >/dev/null 2>&1
command -v beszel-agent || ls /usr/bin/beszel-agent
echo "$KEYB64" | base64 -d > /opt/beszel-agent/id_ed25519 2>/dev/null || true
mkdir -p /opt/beszel-agent
echo "$KEYB64" | base64 -d > /opt/beszel-agent/id_ed25519
chmod 600 /opt/beszel-agent/id_ed25519
cp /opt/beszel-agent/id_ed25519 /etc/beszel-agent.key 2>/dev/null
cat > /etc/systemd/system/beszel-agent.service <<'UNIT'
[Unit]
Description=Beszel Agent
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/sh -c 'KEY="$(cat /opt/beszel-agent/id_ed25519)" exec /usr/bin/beszel-agent'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now beszel-agent >/dev/null 2>&1
systemctl restart beszel-agent
sleep 6
echo -n "beszel-agent: "; systemctl is-active beszel-agent
echo "binary: $(ls -la /usr/bin/beszel-agent | awk '{print $5}') bytes"
journalctl -u beszel-agent -n 3 --no-pager 2>/dev/null | tail -3
