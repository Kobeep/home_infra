#!/usr/bin/env bash
set -euo pipefail

SSH_BASE="${SSH_BASE:-/var/jenkins_home/.ssh}"
HOST_NAME="${HOST_NAME:?Need HOST_NAME}"
REMOTE_HOST="${REMOTE_HOST:?Need REMOTE_HOST}"
REMOTE_USER="${REMOTE_USER:?Need REMOTE_USER}"
REMOTE_KUBECONFIG="${REMOTE_KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

HASS_LOCAL="${HASS_LOCAL:-hass-config}"
DASHY_LOCAL="${DASHY_LOCAL:-dashy-config}"
GRAFANA_LOCAL="${GRAFANA_LOCAL:-grafana-config}"

KEY_PATH="${SSH_BASE}/${HOST_NAME}/id_rsa"

# run sudo kubectl remotely
kc() {
  ssh -i "${KEY_PATH}" -T -o StrictHostKeyChecking=no -o LogLevel=ERROR \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl $*"
}

# find first pod matching fragment
find_pod() {
  kc -n "$1" get pods --no-headers | awk "/$2/ {print \$1; exit}"
}

# restore a directory into pod
restore_dir() {
  ns=$1; frag=$2; path=$3; dir=$4
  pod=$(find_pod "$ns" "$frag")
  [[ -z "$pod" ]] && { echo "⚠️ $frag pod not found in $ns"; return; }
  echo "→ Restoring $dir → $ns/$pod:$path"
  tar cf - -C "$dir" . \
    | ssh -i "${KEY_PATH}" -T -o StrictHostKeyChecking=no -o LogLevel=ERROR \
      "${REMOTE_USER}@${REMOTE_HOST}" \
      "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n $ns exec -i $pod -- tar xf - -C $path"
}

# restore Dashy via file upload + ConfigMap
restore_dashy() {
  local file="${DASHY_LOCAL}/conf.yml"
  [[ ! -f "$file" ]] && { echo "⚠️ $file missing; skip Dashy"; return; }

  echo "→ Uploading Dashy config"
  scp -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
    "$file" "${REMOTE_USER}@${REMOTE_HOST}:/tmp/dashy-conf.yml"

  echo "→ Applying Dashy ConfigMap"
  kc -n monitoring create configmap dashy-config \
     --from-file=conf.yml=/tmp/dashy-conf.yml \
     --dry-run=client -o yaml \
  | kc apply -f -

  echo "→ Restarting Dashy"
  kc -n monitoring rollout restart deployment dashy

  echo "→ Cleaning up"
  ssh -i "${KEY_PATH}" -T -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${REMOTE_HOST}" rm -f /tmp/dashy-conf.yml
}

# main flow
restore_dir  home       home-assistant   /config          "$HASS_LOCAL"
restore_dashy
restore_dir  monitoring grafana          /var/lib/grafana "$GRAFANA_LOCAL"
