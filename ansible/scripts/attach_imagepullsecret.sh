#!/usr/bin/env bash
set -euo pipefail

# Usage: attach_imagepullsecret.sh <secret_name> <namespace>
SECRET_NAME="${1:?secret name required}"
NAMESPACE="${2:?namespace required}"

existing="$(kubectl get sa default -n "$NAMESPACE" -o jsonpath='{.imagePullSecrets[*].name}' 2>/dev/null || true)"

if echo "$existing" | tr ' ' '\n' | grep -qx "$SECRET_NAME"; then
  echo "Secret $SECRET_NAME already attached to serviceaccount default in $NAMESPACE"
  exit 0
fi

if [ -z "$existing" ]; then
  json_patch='[{"op":"add","path":"/imagePullSecrets","value":[{"name":"'"$SECRET_NAME"'"}]}]'
  if ! kubectl patch sa default -n "$NAMESPACE" --type='json' -p="$json_patch"; then
    echo "INFO =>: **Failed to attach $SECRET_NAME to serviceaccount default in $NAMESPACE**" >&2
    exit 1
  fi
else
  json_patch='[{"op":"add","path":"/imagePullSecrets/-","value":{"name":"'"$SECRET_NAME"'"}}]'
  if ! kubectl patch sa default -n "$NAMESPACE" --type='json' -p="$json_patch"; then
    echo "INFO =>: **Failed to append $SECRET_NAME to serviceaccount default in $NAMESPACE**" >&2
    exit 1
  fi
fi

echo "Attached $SECRET_NAME to default serviceaccount in $NAMESPACE"
