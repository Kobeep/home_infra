#!/bin/bash
set -e

NAMESPACE=home
DEPLOYMENT=homeassistant

echo "Restarting deployment '$DEPLOYMENT' in namespace '$NAMESPACE'..."
kubectl rollout restart deployment "$DEPLOYMENT" -n "$NAMESPACE"

echo "Home Assistant deployment restart initiated."
