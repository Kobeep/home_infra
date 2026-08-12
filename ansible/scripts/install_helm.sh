#!/usr/bin/env bash
set -euo pipefail

# Install Helm via official script
if [ -x /usr/local/bin/helm ]; then
  echo "helm already installed"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "INFO =>: **curl is required to install helm**" >&2
  exit 2
fi

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash - || {
  echo "INFO =>: **Helm install script failed**" >&2
  exit 1
}

echo "helm installed"
