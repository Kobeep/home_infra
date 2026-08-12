#!/usr/bin/env bash
set -euo pipefail

if ! command -v update-ca-certificates >/dev/null 2>&1; then
  echo "INFO =>: **update-ca-certificates not available on this system**" >&2
  exit 2
fi

output=$(update-ca-certificates 2>&1) || {
  echo "INFO =>: **update-ca-certificates failed: $output**" >&2
  exit 1
}

echo "$output"
