#!/usr/bin/env bash
set -euo pipefail

# Usage: apply_kustomize.sh <kustomize_root>
ROOT="${1:-./k8s/}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "INFO =>: **kubectl is not installed or not in PATH**" >&2
  exit 2
fi

kubectl apply -k "$ROOT" || {
  echo "INFO =>: **kubectl apply -k $ROOT failed**" >&2
  exit 1
}

echo "Applied kustomize at $ROOT"
