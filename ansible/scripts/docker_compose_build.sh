#!/usr/bin/env bash
set -euo pipefail

# Usage: docker_compose_build.sh <workdir> <service>
WORKDIR="${1:-.}"
SERVICE="${2:-}" # optional

cd "$WORKDIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "INFO =>: **docker is not installed**" >&2
  exit 2
fi

if [ -n "$SERVICE" ]; then
  docker compose build "$SERVICE" || { echo "INFO =>: **docker compose build failed for $SERVICE**" >&2; exit 1; }
else
  docker compose build || { echo "INFO =>: **docker compose build failed**" >&2; exit 1; }
fi

echo "docker compose build completed"
