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

fetch_pod_data(){
  local ns="$1" namefrag="$2" podpath="$3" localdir="$4" mode="$5"
  mkdir -p "${localdir}"
  pod=$(ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n ${ns} get pods --no-headers | grep ${namefrag} | awk '{print \$1}'" \
        || true)
  if [[ -n "${pod}" ]]; then
    echo "⟳ Found ${namefrag} pod: ${pod}"
    if [[ "${mode}" == "dir" ]]; then
      ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n ${ns} cp ${pod}:${podpath} -" \
        | tar -xz -C "${localdir}"
    else
      ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n ${ns} cp ${pod}:${podpath} -" \
        > "${localdir}/$(basename ${podpath})"
    fi
  else
    echo "⚠️ Pod matching '${namefrag}' not found in ns '${ns}'; skipping."
  fi
}

rm -rf "${HASS_LOCAL}" "${DASHY_LOCAL}" "${GRAFANA_LOCAL}"

# Home Assistant (namespace home, katalog /config)
fetch_pod_data home              home-assistant   /config            "${HASS_LOCAL}"    dir

# Dashy       (namespace monitoring, plik conf.yml)
fetch_pod_data monitoring        dashy            /app/public/conf.yml "${DASHY_LOCAL}"  file

# Grafana     (namespace monitoring, katalog /var/lib/grafana)
fetch_pod_data monitoring        grafana          /var/lib/grafana   "${GRAFANA_LOCAL}" dir
