#!/usr/bin/env bash
# Fix hairpin NAT for k3d clusters
# This allows connections from the host to its own external IP when Docker is forwarding ports

set -e

echo "INFO=> Fixing hairpin NAT for k3d cluster access..."

# Get the host's primary IP
HOST_IP=$(ip route get 1.1.1.1 | awk '{print $7}' | head -1)
echo "INFO=> Host IP: $HOST_IP"

# Check if rule already exists
if sudo iptables -t nat -C POSTROUTING -s "$HOST_IP" -d "$HOST_IP" -j MASQUERADE 2>/dev/null; then
    echo "INFO=> Hairpin NAT rule already exists, skipping"
else
    echo "INFO=> Adding hairpin NAT rule..."
    sudo iptables -t nat -A POSTROUTING -s "$HOST_IP" -d "$HOST_IP" -j MASQUERADE
    echo "INFO=> Hairpin NAT rule added successfully"
fi

# Also add a rule for localhost to external IP
if ! sudo iptables -t nat -C POSTROUTING -s 127.0.0.1 -d "$HOST_IP" -j MASQUERADE 2>/dev/null; then
    sudo iptables -t nat -A POSTROUTING -s 127.0.0.1 -d "$HOST_IP" -j MASQUERADE
fi

echo "INFO=> Hairpin NAT fix complete!"
echo ""
echo "You can now access services from:"
echo "  - localhost: http://localhost:80"
echo "  - external IP: http://$HOST_IP:80"
echo ""
