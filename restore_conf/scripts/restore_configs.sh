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
  local ns=$1 frag=$2
  kc -n "${ns}" get pods --no-headers \
    | awk "/${frag}/ {print \$1; exit}"
}

restore_dir() {
  local ns=$1 frag=$2 remote_path=$3 local_dir=$4
  local pod
  pod=$(find_pod "${ns}" "${frag}")
  if [[ -z "$pod" ]]; then
    echo "⚠️ Pod '${frag}' not found in '${ns}'; skipping."
    return
  fi
  echo "⟳ Restoring dir '${local_dir}' → ${ns}/${pod}:${remote_path}"
  tar cf - -C "${local_dir}" . \
    | ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no \
      "${REMOTE_USER}@${REMOTE_HOST}" \
      "sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n ${ns} exec -i ${pod} -- tar xf - -C ${remote_path}"
}

restore_dir home              home-assistant   /config            "${HASS_LOCAL}"

echo "⟳ Creating/updating ConfigMap 'dashy-config' from ${DASHY_LOCAL}/conf.yml"
ssh -i "${KEY_PATH}" -o StrictHostKeyChecking=no "${REMOTE_USER}@${REMOTE_HOST}" <<EOF
sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n monitoring create configmap dashy-config \\
  --from-file=conf.yml=- < ${DASHY_LOCAL}/conf.yml \\
  --dry-run=client -o yaml | kubectl apply -f -
sudo env KUBECONFIG=${REMOTE_KUBECONFIG} kubectl -n monitoring rollout restart deployment dashy
EOF

restore_dir monitoring        grafana          /var/lib/grafana   "${GRAFANA_LOCAL}"
