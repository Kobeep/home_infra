#!/bin/bash
set -e

NAMESPACE=monitoring
DEPLOYMENT=dashy

echo "Restarting deployment '$DEPLOYMENT' in namespace '$NAMESPACE'..."
kubectl rollout restart deployment "$DEPLOYMENT" -n "$NAMESPACE"

echo "Dashy deployment restart initiated."
