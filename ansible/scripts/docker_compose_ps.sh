#!/usr/bin/env bash
set -euo pipefail

# Usage: docker_compose_ps.sh <workdir>
WORKDIR="${1:-.}"

cd "$WORKDIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "INFO =>: **docker is not installed**" >&2
  exit 2
fi

docker compose ps || { echo "INFO =>: **docker compose ps failed**" >&2; exit 1; }

echo "docker compose ps completed"
