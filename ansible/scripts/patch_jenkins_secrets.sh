#!/usr/bin/env bash
set -euo pipefail

# Usage: patch_jenkins_secrets.sh <json_patch>
PATCH="${1:?json patch required}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "INFO =>: **kubectl is not installed or not in PATH**" >&2
  exit 2
fi

if ! kubectl patch secret jenkins-secrets -n jenkins --type merge -p "$PATCH"; then
  echo "INFO =>: **Failed to patch jenkins-secrets with provided patch**" >&2
  exit 1
fi

echo "Patched jenkins-secrets"
