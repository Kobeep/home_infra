#!/bin/bash
set -e

INVENTORY="$1"
PLAYBOOK="$2"

echo "🚀 Run Ansible..."
ansible-playbook -i "$INVENTORY" "$PLAYBOOK"
