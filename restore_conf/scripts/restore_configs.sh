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

find_pod() {
  local ns=$1 namefrag=$2
  kc -n "${ns}" get pods --no-headers \
    | awk "/${namefrag}/ {print \$1; exit}"
}

restore_dir() {
  local ns=$1 namefrag=$2 podpath=$3 localdir=$4
  local pod
  pod=$(find_pod "${ns}" "${namefrag}")
  if [[ -z "$pod" ]]; then
    echo "⚠️ Pod '${namefrag}' not found in '${ns}'; skipping."
    return
  fi
  echo "⟳ Restoring dir '${localdir}' → ${ns}/${pod}:${podpath}"
  tar cf - -C "${localdir}" . \
    | ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
      "${REMOTE_USER}@${REMOTE_HOST}" \
      "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n ${ns} exec -i ${pod} -- tar xf - -C ${podpath}"
}

restore_file() {
  local ns=$1 namefrag=$2 podpath=$3 localfile=$4
  local pod
  pod=$(find_pod "${ns}" "${namefrag}")
  if [[ -z "$pod" ]]; then
    echo "⚠️ Pod '${namefrag}' not found in '${ns}'; skipping."
    return
  fi
  echo "⟳ Restoring file '${localfile}' → ${ns}/${pod}:${podpath}"
  cat "${localfile}" \
    | ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
      "${REMOTE_USER}@${REMOTE_HOST}" \
      "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n ${ns} exec -i ${pod} -- sh -c 'cat > ${podpath}'"
}

restore_dir  home       home-assistant   /config            "${HASS_LOCAL}"
restore_file monitoring dashy            /app/public/conf.yml "${DASHY_LOCAL}/conf.yml"
restore_dir  monitoring grafana          /var/lib/grafana   "${GRAFANA_LOCAL}"
