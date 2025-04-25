#!/usr/bin/env bash
set -euxo pipefail

# konfiguracja (możesz to też przekazać jako argumenty)
SSH_BASE="${SSH_BASE:-/var/jenkins_home/.ssh}"
HOST_NAME="${HOST_NAME:?Need HOST_NAME}"
REMOTE_HOST="${REMOTE_HOST:?Need REMOTE_HOST}"
REMOTE_USER="${REMOTE_USER:?Need REMOTE_USER}"
REMOTE_KUBECONFIG="${REMOTE_KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

HASS_LOCAL="${HASS_LOCAL:-hass-config}"
DASHY_LOCAL="${DASHY_LOCAL:-dashy-config}"
GRAFANA_LOCAL="${GRAFANA_LOCAL:-grafana-config}"

KEY_PATH="${SSH_BASE}/${HOST_NAME}/id_rsa"

function fetch_ha() {
  mkdir -p "${HASS_LOCAL}"
  local pod
  pod=$(ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n home get pod -l app.kubernetes.io/instance=home-assistant -o jsonpath='{.items[0].metadata.name}' 2>/dev/null" \
    || true)
  if [[ -n "$pod" ]]; then
    echo "⟳ HA pod: $pod"
    ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
      "${REMOTE_USER}@${REMOTE_HOST}" \
      "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n home cp ${pod}:/config -" \
      | tar -xz -C "${HASS_LOCAL}"
  else
    echo "⚠️ HA pod not found; skipping."
  fi
}

function fetch_dashy() {
  mkdir -p "${DASHY_LOCAL}"
  local pod
  pod=$(ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n monitoring get pod -l app.kubernetes.io/instance=dashy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null" \
    || true)
  if [[ -n "$pod" ]]; then
    echo "⟳ Dashy pod: $pod"
    ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
      "${REMOTE_USER}@${REMOTE_HOST}" \
      "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n monitoring cp ${pod}:/app/public/conf.yml -" \
      > "${DASHY_LOCAL}/conf.yml"
  else
    echo "⚠️ Dashy pod not found; skipping."
  fi
}

function fetch_grafana() {
  mkdir -p "${GRAFANA_LOCAL}"
  local pod
  pod=$(ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n monitoring get pod -l app.kubernetes.io/instance=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null" \
    || true)
  if [[ -n "$pod" ]]; then
    echo "⟳ Grafana pod: $pod"
    ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
      "${REMOTE_USER}@${REMOTE_HOST}" \
      "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n monitoring cp ${pod}:/var/lib/grafana -" \
      | tar -xz -C "${GRAFANA_LOCAL}"
  else
    echo "⚠️ Grafana pod not found; skipping."
  fi
}

# główny flow
rm -rf "${HASS_LOCAL}" "${DASHY_LOCAL}" "${GRAFANA_LOCAL}"
fetch_ha
fetch_dashy
fetch_grafana
