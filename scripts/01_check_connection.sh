#!/bin/bash
set -e

HOST="$1"

echo "🔌 Testing connection to $HOST..."
ping -c 3 "$HOST"
