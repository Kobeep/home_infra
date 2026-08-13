#!/usr/bin/env bash
set -euo pipefail

# Usage: docker_compose_pull.sh <workdir>
WORKDIR="${1:-.}"

cd "$WORKDIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "INFO =>: **docker is not installed**" >&2
  exit 2
fi

docker compose pull --ignore-buildable || { echo "INFO =>: **docker compose pull failed**" >&2; exit 1; }

echo "docker compose pull completed"
