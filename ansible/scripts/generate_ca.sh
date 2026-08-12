#!/usr/bin/env bash
set -euo pipefail

# Usage: generate_ca.sh <key_path> <crt_path>
KEY_PATH="${1:?key path}"
CRT_PATH="${2:?crt path}"

if [ -f "$KEY_PATH" ]; then
  echo "CA key already exists at $KEY_PATH"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "INFO =>: **openssl not installed**" >&2
  exit 2
fi

openssl req -x509 -nodes -newkey rsa:4096 -keyout "$KEY_PATH" -out "$CRT_PATH" -days 3650 -subj /CN=homelab-local-ca || {
  echo "INFO =>: **Failed to generate CA keypair**" >&2
  exit 1
}

echo "Generated CA key and certificate at $KEY_PATH and $CRT_PATH"
