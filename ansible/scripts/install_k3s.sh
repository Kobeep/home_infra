#!/usr/bin/env bash
set -euo pipefail

# Usage: install_k3s.sh <k3s_version> <server_ip> <install_opts>
K3S_VERSION="${1:-}"
SERVER_IP="${2:-}"
INSTALL_OPTS="${3:---write-kubeconfig-mode 644 --disable traefik}"

if [ -x /usr/local/bin/k3s ]; then
  echo "k3s already installed"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "INFO =>: **curl not available to install k3s**" >&2
  exit 2
fi

export INSTALL_K3S_VERSION="$K3S_VERSION"
export INSTALL_K3S_EXEC="$INSTALL_OPTS --tls-san $SERVER_IP --node-external-ip $SERVER_IP"

curl -sfL https://get.k3s.io | sh - || {
  echo "INFO =>: **k3s installation script failed**" >&2
  exit 1
}

echo "k3s installed"
