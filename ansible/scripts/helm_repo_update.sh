#!/usr/bin/env bash
set -euo pipefail

# Usage: helm_repo_update.sh <name> <url>
NAME="${1:-stable}"
URL="${2:-https://charts.helm.sh/stable}"

if ! command -v helm >/dev/null 2>&1; then
  echo "INFO =>: **helm is not installed**" >&2
  exit 2
fi

helm repo add "$NAME" "$URL" 2>/dev/null || true
helm repo update || { echo "INFO =>: **helm repo update failed**" >&2; exit 1; }

echo "Helm repos updated"
