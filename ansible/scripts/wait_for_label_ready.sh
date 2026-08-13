#!/usr/bin/env bash
set -euo pipefail

# Usage: wait_for_label_ready.sh <namespace> <label_selector> <timeout_seconds>
NAMESPACE="${1:?namespace}"
LABEL="${2:?label selector}"
TIMEOUT="${3:-180s}"

if ! kubectl wait --namespace "$NAMESPACE" --for=condition=ready pod --selector="$LABEL" --timeout="$TIMEOUT"; then
  echo "INFO =>: **Pods with selector $LABEL in namespace $NAMESPACE did not become ready within $TIMEOUT**" >&2
  exit 1
fi

echo "Pods with selector $LABEL in $NAMESPACE are ready"
