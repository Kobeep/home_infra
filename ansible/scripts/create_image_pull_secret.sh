#!/usr/bin/env bash
set -euo pipefail

# Usage: create_image_pull_secret.sh <secret_name> <server> <username> <password> <email> <namespace>
secret_name="${1:?secret_name required}"
server="${2:?server required}"
username="${3:?username required}"
password="${4:?password required}"
email="${5:-noreply@local.invalid}"
namespace="${6:-default}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "INFO =>: **kubectl is not installed or not in PATH**" >&2
  exit 2
fi

yaml=$(kubectl create secret docker-registry "$secret_name" --docker-server="$server" --docker-username="$username" --docker-password="$password" --docker-email="$email" --namespace="$namespace" --dry-run=client -o yaml)
if [ -z "$yaml" ]; then
  echo "INFO =>: **Failed to create secret manifest for $secret_name**" >&2
  exit 1
fi

if ! printf '%s' "$yaml" | kubectl apply -f -; then
  echo "INFO =>: **Failed to apply secret $secret_name to namespace $namespace**" >&2
  exit 1
fi

echo "Applied secret $secret_name to $namespace"
