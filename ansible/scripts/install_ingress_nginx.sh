#!/usr/bin/env bash
set -euo pipefail

# Usage: install_ingress_nginx.sh <kustomize_path>
KUSTOMIZE_PATH="${1:-./k8s/ingress-nginx/}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "INFO =>: **kubectl is not installed or not in PATH**" >&2
  exit 2
fi

kubectl apply -k "${KUSTOMIZE_PATH}" || {
  echo "INFO =>: **Failed to apply ingress-nginx kustomize at ${KUSTOMIZE_PATH}**" >&2
  exit 1
}

echo "Applied ingress-nginx from ${KUSTOMIZE_PATH}"
