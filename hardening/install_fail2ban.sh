#!/bin/bash
# Install fail2ban to protect SSH, with admin/control IPs allowlisted so
# legitimate management/agent traffic is never banned.
# Run as: sudo bash <this>.sh
set -e
export DEBIAN_FRONTEND=noninteractive

# Admin/control IPs that must NEVER be banned
IGNOREIP="127.0.0.1/8 ::1 172.16.0.18 172.16.0.11 172.16.0.210 172.16.0.133 172.16.0.227"

echo "== installing fail2ban =="
apt-get update -qq >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban >/dev/null 2>&1 || \
  { apt-get install -y -qq fail2ban >/dev/null 2>&1; }

echo "== writing /etc/fail2ban/jail.local (ignoreip allowlist + sshd jail) =="
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
ignoreip = $IGNOREIP

[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime  = 600
EOF

echo "== enable + start =="
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban
sleep 3
echo "== status =="
fail2ban-client status 2>/dev/null | head -8
systemctl is-active fail2ban
echo "DONE"
