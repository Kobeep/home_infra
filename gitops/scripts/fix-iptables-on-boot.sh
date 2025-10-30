#!/usr/bin/env bash
set -euo pipefail

# Fix iptables for k3d networking on boot
# This script should be run at system startup before k3d containers start

echo "[$(date)] Starting iptables cleanup for k3d..."

# Flush all iptables rules
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -t raw -F

# Set default policies to ACCEPT
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

echo "[$(date)] iptables cleaned up successfully"

# Optional: Add hairpin NAT rules if needed
# This allows server to connect to its own external IP
EXTERNAL_IP="192.168.1.16"
DOCKER_NETWORKS="172.19.0.0/16 172.20.0.0/16"

for network in $DOCKER_NETWORKS; do
    iptables -t nat -A POSTROUTING -s "${network}" -d "${network}" -j MASQUERADE
    echo "[$(date)] Added MASQUERADE rule for ${network}"
done

echo "[$(date)] iptables fix completed!"
