#!/usr/bin/env bash
set -euo pipefail

# Quick backup trigger script
# Wrapper for easy manual backup execution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="${1:-home-prod}"

echo "🔄 Triggering backup for cluster: ${CLUSTER_NAME}"
echo ""

# Check if cluster exists
if ! kubectl config get-contexts "k3d-${CLUSTER_NAME}" &>/dev/null; then
    echo "❌ Cluster 'k3d-${CLUSTER_NAME}' not found"
    echo ""
    echo "Available clusters:"
    kubectl config get-contexts | grep k3d
    exit 1
fi

# Run backup
CLUSTER_NAME="${CLUSTER_NAME}" "${SCRIPT_DIR}/backup-pvcs.sh"

echo ""
echo "✅ Backup completed!"
echo ""
echo "To push backup to remote git repository:"
echo "  cd $(dirname ${SCRIPT_DIR})"
echo "  git push"
