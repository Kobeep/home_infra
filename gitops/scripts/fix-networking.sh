#!/usr/bin/env bash
set -euo pipefail

# Quick fix script for k3d networking issues
# Run this when external access to services stops working

echo "🔧 Starting k3d networking quick fix..."
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root (use sudo)"
   exit 1
fi

echo "1️⃣ Flushing iptables rules..."
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F
echo "   ✓ iptables flushed"

echo ""
echo "2️⃣ Setting default policies..."
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
echo "   ✓ Policies set to ACCEPT"

echo ""
echo "3️⃣ Adding hairpin NAT rules..."
EXTERNAL_IP="192.168.1.16"
DOCKER_NETWORKS="172.19.0.0/16 172.20.0.0/16"

for network in $DOCKER_NETWORKS; do
    iptables -t nat -A POSTROUTING -s "${network}" -d "${network}" -j MASQUERADE
    echo "   ✓ MASQUERADE rule added for ${network}"
done

echo ""
echo "4️⃣ Restarting Docker..."
systemctl restart docker
echo "   ✓ Docker restarted"

echo ""
echo "5️⃣ Waiting for containers to restart (30s)..."
sleep 30
echo "   ✓ Wait completed"

echo ""
echo "6️⃣ Checking service status..."

# Check if kubectl is available
if command -v kubectl &> /dev/null; then
    echo ""
    echo "Pod status:"
    kubectl get pods -n argocd | head -5
    kubectl get pods -n home-assistant 2>/dev/null || echo "   (home-assistant namespace not ready yet)"

    echo ""
    echo "Ingress status:"
    kubectl get ingress --all-namespaces 2>/dev/null || echo "   (Ingress not ready yet)"
else
    echo "   kubectl not found, skipping status check"
fi

echo ""
echo "7️⃣ Testing local connectivity..."
if curl -s -I http://localhost:80 -H 'Host: dashy.kobeep.pl' | head -1; then
    echo "   ✓ Local access works!"
else
    echo "   ⚠️  Local access not working yet (may need more time)"
fi

echo ""
echo "✅ Quick fix completed!"
echo ""
echo "Next steps:"
echo "  1. Wait 1-2 minutes for all pods to be ready"
echo "  2. Test from your desktop: curl http://192.168.1.16 -H 'Host: dashy.kobeep.pl'"
echo "  3. Check pod status: kubectl get pods --all-namespaces"
echo ""
echo "If issues persist, check:"
echo "  - Docker logs: journalctl -u docker -n 50"
echo "  - k3d container logs: docker logs k3d-home-prod-serverlb"
echo "  - iptables rules: iptables -t nat -L -n -v | grep 80"
echo ""
