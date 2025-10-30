#!/usr/bin/env bash
set -euo pipefail

# GitOps PVC Restore Script for k3d Clusters
# Restores persistent data from git repository to running services
# Version: 1.0.0 (adapted from Jenkins restore pipeline)

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

# Namespace mappings for k3d GitOps
NAMESPACE_HA="home-assistant"
NAMESPACE_DASHY="dashy"
NAMESPACE_GRAFANA="monitoring"
NAMESPACE_ADGUARD="adguard"
NAMESPACE_OPENWEBUI="openwebui"

# Restore options (can be overridden via environment)
RESTORE_HOME_ASSISTANT="${RESTORE_HOME_ASSISTANT:-true}"
RESTORE_DASHY="${RESTORE_DASHY:-true}"
RESTORE_GRAFANA="${RESTORE_GRAFANA:-true}"
RESTORE_ADGUARD="${RESTORE_ADGUARD:-true}"
RESTORE_OPENWEBUI="${RESTORE_OPENWEBUI:-true}"

# Wait settings
MAX_WAIT_PODS="${MAX_WAIT_PODS:-300}"  # 5 minutes max wait for pods

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $*"
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

# Wait for pod to be running
wait_for_pod() {
    local ns=$1
    local fragment=$2
    local max_wait=${3:-${MAX_WAIT_PODS}}

    log_info "Waiting for pod matching '${fragment}' in namespace '${ns}' (max ${max_wait}s)..."

    local elapsed=0
    local interval=5

    while [[ ${elapsed} -lt ${max_wait} ]]; do
        local pod=$(find_pod "${ns}" "${fragment}")

        if [[ -n "${pod}" ]]; then
            log_info "  ✓ Pod ${pod} is running"
            echo "${pod}"
            return 0
        fi

        sleep ${interval}
        elapsed=$((elapsed + interval))
        log_debug "  Waiting... (${elapsed}/${max_wait}s)"
    done

    log_error "  ✗ Timeout waiting for pod in ${ns}"
    return 1
}

# Restore entire directory from local to pod
restore_dir() {
    local ns=$1
    local fragment=$2
    local path=$3
    local dir=$4

    if [[ ! -d "${dir}" ]]; then
        log_warn "Local directory ${dir} does not exist, skipping restore"
        return 1
    fi

    log_info "Restoring ${dir} → ${ns}/<pod>:${path}"

    local pod=$(wait_for_pod "${ns}" "${fragment}")

    if [[ -z "${pod}" ]]; then
        log_error "Cannot restore: pod not found or not running"
        return 1
    fi

    # Stream tar archive to pod
    tar cf - -C "${dir}" . \
        | kc -n "${ns}" exec -i "${pod}" -- tar xf - -C "${path}"

    if [[ $? -eq 0 ]]; then
        local file_count=$(find "${dir}" -type f | wc -l)
        log_info "  ✓ Restored ${file_count} files"
        return 0
    else
        log_error "  ✗ Restore failed for ${ns}/${pod}"
        return 1
    fi
}

# Restore single file from local to pod (via ConfigMap)
restore_dashy_configmap() {
    local file="${DASHY_LOCAL}/conf.yml"

    if [[ ! -f "${file}" ]]; then
        log_warn "Dashy config file ${file} does not exist, skipping restore"
        return 1
    fi

    log_info "Restoring Dashy configuration via ConfigMap"

    # Wait for namespace to exist
    local max_wait=60
    local elapsed=0
    while ! kc get namespace "${NAMESPACE_DASHY}" &>/dev/null && [[ ${elapsed} -lt ${max_wait} ]]; do
        sleep 5
        elapsed=$((elapsed + 5))
    done

    if ! kc get namespace "${NAMESPACE_DASHY}" &>/dev/null; then
        log_error "Namespace ${NAMESPACE_DASHY} does not exist"
        return 1
    fi

    # Create/update ConfigMap
    kc -n "${NAMESPACE_DASHY}" create configmap dashy-config \
        --from-file=conf.yml="${file}" \
        --dry-run=client --save-config -o yaml \
        | kc apply -f -

    if [[ $? -eq 0 ]]; then
        log_info "  ✓ ConfigMap updated"

        # Restart Dashy deployment to pick up new config
        log_info "Restarting Dashy deployment..."
        if kc -n "${NAMESPACE_DASHY}" rollout restart deployment dashy &>/dev/null; then
            log_info "  ✓ Dashy deployment restarted"
        else
            log_warn "  ✗ Failed to restart Dashy (may not exist yet)"
        fi

        return 0
    else
        log_error "  ✗ Failed to update ConfigMap"
        return 1
    fi
}

# Restore Home Assistant
restore_home_assistant() {
    if [[ "${RESTORE_HOME_ASSISTANT}" != "true" ]]; then
        log_info "Skipping Home Assistant restore (disabled)"
        return 0
    fi

    log_info "=== Restoring Home Assistant ==="
    restore_dir "${NAMESPACE_HA}" "home-assistant" "/config" "${HASS_LOCAL}"
}

# Restore Dashy
restore_dashy() {
    if [[ "${RESTORE_DASHY}" != "true" ]]; then
        log_info "Skipping Dashy restore (disabled)"
        return 0
    fi

    log_info "=== Restoring Dashy ==="
    restore_dashy_configmap
}

# Restore Grafana
restore_grafana() {
    if [[ "${RESTORE_GRAFANA}" != "true" ]]; then
        log_info "Skipping Grafana restore (disabled)"
        return 0
    fi

    log_info "=== Restoring Grafana ==="
    restore_dir "${NAMESPACE_GRAFANA}" "grafana" "/var/lib/grafana" "${GRAFANA_LOCAL}"
}

# Restore AdGuard Home
restore_adguard() {
    if [[ "${RESTORE_ADGUARD}" != "true" ]]; then
        log_info "Skipping AdGuard Home restore (disabled)"
        return 0
    fi

    log_info "=== Restoring AdGuard Home ==="

    local success=true

    # Restore work directory
    if [[ -d "${ADGUARD_LOCAL}/work" ]]; then
        restore_dir "${NAMESPACE_ADGUARD}" "adguard" "/opt/adguardhome/work" "${ADGUARD_LOCAL}/work" || success=false
    else
        log_warn "AdGuard work directory not found: ${ADGUARD_LOCAL}/work"
    fi

    # Restore conf directory
    if [[ -d "${ADGUARD_LOCAL}/conf" ]]; then
        restore_dir "${NAMESPACE_ADGUARD}" "adguard" "/opt/adguardhome/conf" "${ADGUARD_LOCAL}/conf" || success=false
    else
        log_warn "AdGuard conf directory not found: ${ADGUARD_LOCAL}/conf"
    fi

    [[ "${success}" == "true" ]]
}

# Restore OpenWebUI
restore_openwebui() {
    if [[ "${RESTORE_OPENWEBUI}" != "true" ]]; then
        log_info "Skipping OpenWebUI restore (disabled)"
        return 0
    fi

    log_info "=== Restoring OpenWebUI ==="

    if [[ -d "${OPENWEBUI_LOCAL}" ]]; then
        restore_dir "${NAMESPACE_OPENWEBUI}" "openwebui" "/app/backend/data" "${OPENWEBUI_LOCAL}"
    else
        log_warn "OpenWebUI backup directory not found: ${OPENWEBUI_LOCAL}"
        return 1
    fi
}

# Verify backups exist
verify_backups() {
    log_info "=== Verifying Backup Data ==="

    local missing=()

    [[ "${RESTORE_HOME_ASSISTANT}" == "true" && ! -d "${HASS_LOCAL}" ]] && missing+=("Home Assistant (${HASS_LOCAL})")
    [[ "${RESTORE_DASHY}" == "true" && ! -f "${DASHY_LOCAL}/conf.yml" ]] && missing+=("Dashy (${DASHY_LOCAL}/conf.yml)")
    [[ "${RESTORE_GRAFANA}" == "true" && ! -d "${GRAFANA_LOCAL}" ]] && missing+=("Grafana (${GRAFANA_LOCAL})")
    [[ "${RESTORE_ADGUARD}" == "true" && ! -d "${ADGUARD_LOCAL}" ]] && missing+=("AdGuard Home (${ADGUARD_LOCAL})")
    [[ "${RESTORE_OPENWEBUI}" == "true" && ! -d "${OPENWEBUI_LOCAL}" ]] && missing+=("OpenWebUI (${OPENWEBUI_LOCAL})")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing backup data:"
        for item in "${missing[@]}"; do
            log_error "  - ${item}"
        done
        return 1
    fi

    log_info "All required backup data present ✓"
    return 0
}

# Generate restore report
generate_report() {
    log_info "=== Restore Report ==="

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo ""
    echo "Restore completed: ${timestamp}"
    echo "Cluster: ${CLUSTER_NAME}"
    echo ""
    echo "Services Restored:"

    [[ "${RESTORE_HOME_ASSISTANT}" == "true" ]] && echo "  ✓ Home Assistant"
    [[ "${RESTORE_DASHY}" == "true" ]] && echo "  ✓ Dashy"
    [[ "${RESTORE_GRAFANA}" == "true" ]] && echo "  ✓ Grafana"
    [[ "${RESTORE_ADGUARD}" == "true" ]] && echo "  ✓ AdGuard Home"
    [[ "${RESTORE_OPENWEBUI}" == "true" ]] && echo "  ✓ OpenWebUI"

    echo ""
    echo "Note: Services may take a few minutes to fully restart with restored configurations"
    echo ""
}

# Main execution
main() {
    log_info "Starting GitOps PVC Restore for cluster: ${CLUSTER_NAME}"
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

    # Verify backup data exists
    if ! verify_backups; then
        log_error "Cannot proceed without backup data"
        exit 1
    fi
    echo ""

    # Execute restores (continue on individual failures but track them)
    local failed_services=()

    restore_home_assistant || failed_services+=("Home Assistant")
    echo ""

    restore_dashy || failed_services+=("Dashy")
    echo ""

    restore_grafana || failed_services+=("Grafana")
    echo ""

    restore_adguard || failed_services+=("AdGuard Home")
    echo ""

    restore_openwebui || failed_services+=("OpenWebUI")
    echo ""

    # Generate report
    generate_report

    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_warn "Restore completed with failures:"
        for service in "${failed_services[@]}"; do
            log_warn "  - ${service}"
        done
        log_warn "Check logs above for details"
        exit 1
    else
        log_info "Restore process completed successfully! ✓"
    fi
}

# Run main function
main "$@"
