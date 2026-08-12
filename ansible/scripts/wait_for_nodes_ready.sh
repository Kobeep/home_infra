#!/usr/bin/env bash
set -euo pipefail

# Usage: wait_for_nodes_ready.sh <timeout>
TIMEOUT="${1:-180s}"

if ! kubectl wait --for=condition=Ready node --all --timeout="$TIMEOUT"; then
  echo "INFO =>: **Nodes did not become Ready within $TIMEOUT**" >&2
  exit 1
fi

echo "All nodes are Ready"
