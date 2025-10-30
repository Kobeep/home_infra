#!/usr/bin/env bash
set -euo pipefail

# GitOps PVC Backup Script for k3d Clusters
# Backs up persistent data from all user-facing services to git repository
# Version: 1.0.0 (adapted from Jenkins backup pipeline)

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-home-prod}"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Backup directories (relative to repo root)
HASS_LOCAL="${BACKUP_BASE_DIR}/hass-config"
DASHY_LOCAL="${BACKUP_BASE_DIR}/dashy-config"
GRAFANA_LOCAL="${BACKUP_BASE_DIR}/grafana-config"
ADGUARD_LOCAL="${BACKUP_BASE_DIR}/adguard-config"
OPENWEBUI_LOCAL="${BACKUP_BASE_DIR}/openwebui-config"

# Namespace mappings for k3d GitOps (updated from old k3s structure)
NAMESPACE_HA="home-assistant"
NAMESPACE_DASHY="dashy"
NAMESPACE_GRAFANA="monitoring"
NAMESPACE_ADGUARD="adguard"
NAMESPACE_OPENWEBUI="openwebui"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Wrapper for kubectl with context awareness
kc() {
    kubectl --context "k3d-${CLUSTER_NAME}" "$@"
}

# Find first pod matching name fragment in namespace
find_pod() {
    local ns=$1
    local fragment=$2
    kc -n "${ns}" get pods --no-headers 2>/dev/null \
        | awk "/${fragment}/ && \$3 == \"Running\" {print \$1; exit}"
}

# Backup entire directory from pod to local
fetch_dir() {
    local ns=$1
    local podname=$2
    local remotepath=$3
    local localdir=$4

    log_info "Backing up ${ns}/${podname}:${remotepath} → ${localdir}"

    # Remove old backup
    rm -rf "${localdir}"
    mkdir -p "${localdir}"

    # Extract via tar from pod
    kc -n "${ns}" exec "${podname}" -- tar cf - -C "${remotepath}" . \
        | tar xf - -C "${localdir}"

    if [[ $? -eq 0 ]]; then
        local file_count=$(find "${localdir}" -type f | wc -l)
        local size=$(du -sh "${localdir}" | cut -f1)
        log_info "  ✓ Backed up ${file_count} files (${size})"
    else
        log_error "  ✗ Backup failed for ${ns}/${podname}"
        return 1
    fi
}

# Backup single file from pod to local
fetch_file() {
    local ns=$1
    local podname=$2
    local remotefile=$3
    local localfile=$4

    log_info "Backing up ${ns}/${podname}:${remotefile} → ${localfile}"

    mkdir -p "$(dirname "${localfile}")"

    kc -n "${ns}" exec "${podname}" -- cat "${remotefile}" > "${localfile}"

    if [[ $? -eq 0 ]]; then
        local size=$(du -sh "${localfile}" | cut -f1)
        log_info "  ✓ Backed up file (${size})"
    else
        log_error "  ✗ Backup failed for ${ns}/${podname}:${remotefile}"
        return 1
    fi
}

# Backup Home Assistant
backup_home_assistant() {
    log_info "=== Backing up Home Assistant ==="

    local pod=$(find_pod "${NAMESPACE_HA}" "home-assistant")

    if [[ -z "${pod}" ]]; then
        log_warn "Home Assistant pod not found or not running in ${NAMESPACE_HA}"
        return 1
    fi

    fetch_dir "${NAMESPACE_HA}" "${pod}" "/config" "${HASS_LOCAL}"
}

# Backup Dashy
backup_dashy() {
    log_info "=== Backing up Dashy ==="

    local pod=$(find_pod "${NAMESPACE_DASHY}" "dashy")

    if [[ -z "${pod}" ]]; then
        log_warn "Dashy pod not found or not running in ${NAMESPACE_DASHY}"
        return 1
    fi

    fetch_file "${NAMESPACE_DASHY}" "${pod}" "/app/public/conf.yml" "${DASHY_LOCAL}/conf.yml"
}

# Backup Grafana
backup_grafana() {
    log_info "=== Backing up Grafana ==="

    local pod=$(find_pod "${NAMESPACE_GRAFANA}" "grafana")

    if [[ -z "${pod}" ]]; then
        log_warn "Grafana pod not found or not running in ${NAMESPACE_GRAFANA}"
        return 1
    fi

    fetch_dir "${NAMESPACE_GRAFANA}" "${pod}" "/var/lib/grafana" "${GRAFANA_LOCAL}"
}

# Backup AdGuard Home
backup_adguard() {
    log_info "=== Backing up AdGuard Home ==="

    local pod=$(find_pod "${NAMESPACE_ADGUARD}" "adguard")

    if [[ -z "${pod}" ]]; then
        log_warn "AdGuard Home pod not found or not running in ${NAMESPACE_ADGUARD}"
        return 1
    fi

    # Backup work directory
    fetch_dir "${NAMESPACE_ADGUARD}" "${pod}" "/opt/adguardhome/work" "${ADGUARD_LOCAL}/work"

    # Backup conf directory
    fetch_dir "${NAMESPACE_ADGUARD}" "${pod}" "/opt/adguardhome/conf" "${ADGUARD_LOCAL}/conf"
}

# Backup OpenWebUI
backup_openwebui() {
    log_info "=== Backing up OpenWebUI ==="

    local pod=$(find_pod "${NAMESPACE_OPENWEBUI}" "openwebui")

    if [[ -z "${pod}" ]]; then
        log_warn "OpenWebUI pod not found or not running in ${NAMESPACE_OPENWEBUI}"
        return 1
    fi

    fetch_dir "${NAMESPACE_OPENWEBUI}" "${pod}" "/app/backend/data" "${OPENWEBUI_LOCAL}"
}

# Git commit and push backups
commit_backups() {
    log_info "=== Committing backups to git ==="

    cd "${BACKUP_BASE_DIR}"

    # Configure git if needed
    if [[ -z "$(git config user.email)" ]]; then
        git config user.email "backup-bot@homeinfra.local"
        git config user.name "Backup Bot"
    fi

    # Add backup directories
    git add -A hass-config/ dashy-config/ grafana-config/ adguard-config/ openwebui-config/ 2>/dev/null || true

    # Check if there are changes
    if git diff --staged --quiet; then
        log_info "No changes to commit"
        return 0
    fi

    # Commit with timestamp
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    git commit -m "Automated backup: ${timestamp} [${CLUSTER_NAME}]"

    log_info "  ✓ Backup committed locally"

    # Push if remote is configured (optional)
    if git remote get-url origin &>/dev/null; then
        log_info "Pushing to remote repository..."
        if git push; then
            log_info "  ✓ Backup pushed to remote"
        else
            log_warn "  ✗ Failed to push to remote (continuing anyway)"
        fi
    else
        log_warn "No git remote configured, skipping push"
    fi
}

# Generate backup report
generate_report() {
    log_info "=== Backup Report ==="

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo ""
    echo "Backup completed: ${timestamp}"
    echo "Cluster: ${CLUSTER_NAME}"
    echo ""
    echo "Backup Sizes:"

    [[ -d "${HASS_LOCAL}" ]] && echo "  Home Assistant:  $(du -sh "${HASS_LOCAL}" | cut -f1)"
    [[ -d "${DASHY_LOCAL}" ]] && echo "  Dashy:           $(du -sh "${DASHY_LOCAL}" | cut -f1)"
    [[ -d "${GRAFANA_LOCAL}" ]] && echo "  Grafana:         $(du -sh "${GRAFANA_LOCAL}" | cut -f1)"
    [[ -d "${ADGUARD_LOCAL}" ]] && echo "  AdGuard Home:    $(du -sh "${ADGUARD_LOCAL}" | cut -f1)"
    [[ -d "${OPENWEBUI_LOCAL}" ]] && echo "  OpenWebUI:       $(du -sh "${OPENWEBUI_LOCAL}" | cut -f1)"

    echo ""
}

# Main execution
main() {
    log_info "Starting GitOps PVC Backup for cluster: ${CLUSTER_NAME}"
    log_info "Backup base directory: ${BACKUP_BASE_DIR}"

    # Verify kubectl context exists
    if ! kubectl config get-contexts "k3d-${CLUSTER_NAME}" &>/dev/null; then
        log_error "k3d cluster context 'k3d-${CLUSTER_NAME}' not found"
        log_error "Available contexts:"
        kubectl config get-contexts
        exit 1
    fi

    # Verify cluster is accessible
    if ! kc cluster-info &>/dev/null; then
        log_error "Cannot connect to k3d cluster '${CLUSTER_NAME}'"
        exit 1
    fi

    log_info "Cluster connection verified ✓"
    echo ""

    # Execute backups (continue on individual failures)
    backup_home_assistant || log_warn "Home Assistant backup failed"
    echo ""

    backup_dashy || log_warn "Dashy backup failed"
    echo ""

    backup_grafana || log_warn "Grafana backup failed"
    echo ""

    backup_adguard || log_warn "AdGuard Home backup failed"
    echo ""

    backup_openwebui || log_warn "OpenWebUI backup failed"
    echo ""

    # Commit to git
    commit_backups
    echo ""

    # Generate report
    generate_report

    log_info "Backup process completed! ✓"
}

# Run main function
main "$@"
