#!/usr/bin/env bash
set -euo pipefail

# Host-based homelab backup helper for Jenkins
# This script SSHes to the target homelab host and runs the
# Ansible-deployed backup script (/usr/local/bin/homelab-backup-configs).
# It then pulls the produced tarball, extracts it into the workspace
# and copies the expected service directories so Jenkins can commit them.

SSH_BASE="${SSH_BASE:-/var/jenkins_home/.ssh}"
HOST_NAME="${HOST_NAME:?Need HOST_NAME}"
REMOTE_HOST="${REMOTE_HOST:?Need REMOTE_HOST}"
REMOTE_USER="${REMOTE_USER:?Need REMOTE_USER}"

HASS_LOCAL="${HASS_LOCAL:-hass-config}"
DASHY_LOCAL="${DASHY_LOCAL:-dashy-config}"
GRAFANA_LOCAL="${GRAFANA_LOCAL:-grafana-config}"
ADGUARD_LOCAL="${ADGUARD_LOCAL:-adguard-config}"
OPENWEBUI_LOCAL="${OPENWEBUI_LOCAL:-openwebui-config}"

KEY_PATH="${SSH_BASE}/${HOST_NAME}/id_rsa"

if [ ! -f "${KEY_PATH}" ]; then
  echo "ERROR: SSH key not found: ${KEY_PATH}" >&2
  exit 2
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REMOTE_BACKUP_DIR="/tmp/homelab-config-backup-${TIMESTAMP}"
REMOTE_ARCHIVE="/tmp/homelab-config-backup-${TIMESTAMP}.tar.gz"
LOCAL_ARCHIVE="/tmp/homelab-config-backup-${TIMESTAMP}.tar.gz"

SSH_OPTS=( -i "${KEY_PATH}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null )

echo "➡️  Starting host backup: ${REMOTE_USER}@${REMOTE_HOST}"

echo "🔁 Running remote backup script on host..."
ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" sudo /usr/local/bin/homelab-backup-configs "${REMOTE_BACKUP_DIR}"

echo "⬇️  Fetching archive: ${REMOTE_ARCHIVE}"
scp "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_ARCHIVE}" "${LOCAL_ARCHIVE}"

echo "📦 Extracting archive into workspace..."
TMP_EXTRACT_DIR="/tmp/homelab-extract-${TIMESTAMP}"
rm -rf "${TMP_EXTRACT_DIR}"
mkdir -p "${TMP_EXTRACT_DIR}"
tar xzf "${LOCAL_ARCHIVE}" -C "${TMP_EXTRACT_DIR}"

# The archive contains a top-level directory named like the backup dir
EXTRACTED_TOP=$(find "${TMP_EXTRACT_DIR}" -maxdepth 1 -type d -name 'homelab-config-backup-*' -print -quit)
if [ -z "${EXTRACTED_TOP}" ]; then
  echo "ERROR: Extracted archive did not contain expected top-level dir" >&2
  ls -la "${TMP_EXTRACT_DIR}"
  exit 3
fi

echo "📁 Copying backed-up service data into workspace dirs"
mkdir -p "${HASS_LOCAL}" "${DASHY_LOCAL}" "${GRAFANA_LOCAL}" "${ADGUARD_LOCAL}" "${OPENWEBUI_LOCAL}"

# Helper to copy if present
copy_if_exists() {
  local src="$1" dst="$2"
  if [ -e "${src}" ]; then
    echo "  ✓ Installing ${src} -> ${dst}"
    rm -rf "${dst}"
    mkdir -p "$(dirname "${dst}")"
    # If src is a dir, copy contents; if file, copy file
    if [ -d "${src}" ]; then
      cp -r "${src}" "${dst}"
    else
      mkdir -p "$(dirname "${dst}")"
      cp "${src}" "${dst}"
    fi
  else
    echo "  ⚠️  Source not found, skipping: ${src}"
  fi
}

copy_if_exists "${EXTRACTED_TOP}/homeassistant" "${HASS_LOCAL}"
copy_if_exists "${EXTRACTED_TOP}/dashy" "${DASHY_LOCAL}"
copy_if_exists "${EXTRACTED_TOP}/grafana" "${GRAFANA_LOCAL}"
copy_if_exists "${EXTRACTED_TOP}/prometheus" "${TMP_EXTRACT_DIR}/prometheus" || true
copy_if_exists "${EXTRACTED_TOP}/loki" "${TMP_EXTRACT_DIR}/loki" || true
copy_if_exists "${EXTRACTED_TOP}/promtail" "${TMP_EXTRACT_DIR}/promtail" || true
copy_if_exists "${EXTRACTED_TOP}/jenkins" "${TMP_EXTRACT_DIR}/jenkins" || true
copy_if_exists "${EXTRACTED_TOP}/grocy" "${TMP_EXTRACT_DIR}/grocy" || true

echo "🧹 Cleaning up local temporary files"
rm -f "${LOCAL_ARCHIVE}"
rm -rf "${TMP_EXTRACT_DIR}"

echo "🗑️  Removing remote temporary files"
ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" sudo rm -rf "${REMOTE_BACKUP_DIR}" "${REMOTE_ARCHIVE}" || true

echo "✅ Host backup fetched and placed into workspace directories"

exit 0
