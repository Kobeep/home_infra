#!/bin/bash
set -e

HOST="$1"
USER="$2"
KEY_PATH="$3"

echo "🔑 Fetching key SSH from $HOST..."
ssh-copy-id -i "$KEY_PATH" "$USER@$HOST"
