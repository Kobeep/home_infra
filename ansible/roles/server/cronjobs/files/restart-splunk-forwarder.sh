#!/bin/bash
set -e

NAMESPACE=monitoring
DEPLOYMENT=splunk

echo "Restarting deployment '$DEPLOYMENT' in namespace '$NAMESPACE'..."
kubectl rollout restart deployment "$DEPLOYMENT" -n "$NAMESPACE"

echo "Splunk Forwarder deployment restart initiated."
