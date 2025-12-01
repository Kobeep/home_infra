#!/bin/bash
# Secure Home Lab Firewall Configuration

set -e

echo "🔥 Configuring Firewall Rules..."

# Backup current rules
ssh server "sudo iptables-save > /tmp/iptables-backup-\$(date +%Y%m%d-%H%M%S).rules"

# Basic firewall rules
cat << 'EOF' | ssh server "sudo bash"
# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow SSH (change port if you use non-standard)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTP/HTTPS for ingress
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Allow k3s/k3d ports (if needed from specific IPs only)
# Uncomment and adjust if you need external access to k3s API
# iptables -A INPUT -p tcp --dport 6443 -s YOUR_TRUSTED_IP -j ACCEPT

# BLOCK direct access to NodePort range (30000-32767)
iptables -A INPUT -p tcp --dport 30000:32767 -j DROP
iptables -A INPUT -p udp --dport 30000:32767 -j DROP

# Allow ping (ICMP)
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Block everything else
# iptables -P INPUT DROP  # BE CAREFUL - can lock you out!

# Save rules
iptables-save > /etc/iptables/rules.v4 2>/dev/null || \
    (mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4)

echo "✅ Firewall rules applied"
EOF

echo ""
echo "Current firewall rules:"
ssh server "sudo iptables -L INPUT -n -v"

echo ""
echo "⚠️  To make persistent across reboots:"
echo "   sudo apt install iptables-persistent"
echo "   sudo netfilter-persistent save"
