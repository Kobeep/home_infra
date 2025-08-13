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

kc() {
  ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl $*"
}

fetch_dir() {
  local ns=$1 podname=$2 remotepath=$3 localdir=$4
  rm -rf "${localdir}"
  mkdir -p "${localdir}"
  echo "⟳ Archiving dir ${remotepath} from pod ${podname} in ns ${ns}"
  kc -n "${ns}" exec "${podname}" -- tar cf - -C "${remotepath}" . \
    | tar xf - -C "${localdir}"
}

fetch_file() {
  local ns=$1 podname=$2 remotepath=$3 localfile=$4
  mkdir -p "$(dirname "${localfile}")"
  echo "⟳ Fetching file ${remotepath} from pod ${podname} in ns ${ns}"
  kc -n "${ns}" exec "${podname}" -- cat "${remotepath}" \
    > "${localfile}"
}

find_pod() {
  local ns=$1 namefrag=$2
  kc -n "${ns}" get pods --no-headers \
    | awk "/${namefrag}/ {print \$1; exit}"
}

POD=$(find_pod home home-assistant)
if [[ -n "$POD" ]]; then
  fetch_dir  home "$POD" /config              "${HASS_LOCAL}"
else
  echo "⚠️ HA pod not found; skipping."
fi

POD=$(find_pod monitoring dashy)
if [[ -n "$POD" ]]; then
  fetch_file monitoring "$POD" /app/public/conf.yml "${DASHY_LOCAL}/conf.yml"
else
  echo "⚠️ Dashy pod not found; skipping."
fi

POD=$(find_pod monitoring grafana)
if [[ -n "$POD" ]]; then
  fetch_dir  monitoring "$POD" /var/lib/grafana   "${GRAFANA_LOCAL}"
else
  echo "⚠️ Grafana pod not found; skipping."
fi
