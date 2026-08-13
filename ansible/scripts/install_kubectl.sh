#!/usr/bin/env bash
set -euo pipefail

# Usage: install_kubectl.sh <version>
VERSION="${1:-}"

if [ -x /usr/local/bin/kubectl ]; then
  echo "kubectl already installed"
  exit 0
fi

if [ -z "$VERSION" ]; then
  VERSION=$(curl -sS https://dl.k8s.io/release/stable.txt)
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cd "$tmpdir"
curl -LO "https://dl.k8s.io/release/${VERSION}/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/kubectl

echo "kubectl installed"
