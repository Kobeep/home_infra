#!/usr/bin/env bash
set -euo pipefail

# Usage: cert_manager_install.sh <version>
VERSION="${1:-v1.14.4}"

if ! command -v helm >/dev/null 2>&1; then
  echo "INFO =>: **helm is not installed or not in PATH**" >&2
  exit 2
fi

# add jetstack if missing (ignore failures if already exists)
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo update

# apply CRDs directly
if ! kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${VERSION}/cert-manager.crds.yaml"; then
  echo "INFO =>: **Failed to apply cert-manager CRDs for ${VERSION}**" >&2
  exit 1
fi

if ! helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version "${VERSION}" --set crds.enabled=true --timeout 10m0s; then
  echo "INFO =>: **Failed to install/upgrade cert-manager ${VERSION}**" >&2
  exit 1
fi

echo "cert-manager ${VERSION} installed/ensured"
