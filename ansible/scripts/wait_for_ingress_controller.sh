#!/usr/bin/env bash
set -euo pipefail

# Wait until a deployment with given selector exists and pods become ready
NAMESPACE="ingress-nginx"
DEPLOY_LABEL="app.kubernetes.io/name=ingress-nginx"
POD_SELECTOR="app.kubernetes.io/component=controller"
RETRIES=${1:-12}
DELAY=${2:-10}

for i in $(seq 1 "$RETRIES"); do
  names=$(kubectl get deployment -n "$NAMESPACE" -l "$DEPLOY_LABEL" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
  if [ -n "$names" ]; then
    break
  fi
  sleep "$DELAY"
done

if [ -z "$names" ]; then
  echo "INFO =>: **Ingress NGINX deployment did not appear in ${RETRIES} attempts**" >&2
  exit 1
fi

# Wait for controller pod ready
if ! kubectl wait --namespace "$NAMESPACE" --for=condition=ready pod --selector="$POD_SELECTOR" --timeout=180s; then
  echo "INFO =>: **Ingress NGINX controller pod did not become ready within timeout**" >&2
  exit 1
fi

echo "Ingress NGINX is available"
