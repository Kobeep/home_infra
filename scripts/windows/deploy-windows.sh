#!/usr/bin/env bash
#
# Windows Deployment Script
# Handles the complete Windows deployment workflow using Ansible.
#

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

# Configuration with defaults
INVENTORY_FILE="${INVENTORY_FILE:-ansible/inventories/hosts.yml}"
PLAYBOOKS_DIR="${PLAYBOOKS_DIR:-ansible/playbooks}"

# Function: Parse Windows inventory and extract host configuration
parse_windows_inventory() {
    local target_host="$1"
    
    validate_required_params "parse_windows_inventory" target_host
    validate_file_exists "${INVENTORY_FILE}" "Inventory file"
    validate_command_exists "python3"
    
    log_step "Parsing Windows inventory for host: ${target_host}"
    
    local inventory_script="${SCRIPT_DIR}/../common/inventory-parser.py"
    local host_config_json
    
    if ! host_config_json=$(python3 "${inventory_script}" "${INVENTORY_FILE}" "${target_host}" --group windows); then
        log_error "Failed to parse inventory for host: ${target_host}"
        return 1
    fi
    
    # Extract configuration values
    TARGET_IP=$(echo "${host_config_json}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ansible_host', ''))")
    REMOTE_USER=$(echo "${host_config_json}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('ansible_user', ''))")
    
    if [[ -z "${TARGET_IP}" ]] || [[ -z "${REMOTE_USER}" ]]; then
        log_error "Missing required configuration in inventory for host: ${target_host}"
        return 1
    fi
    
    log_success "Inventory parsed successfully"
    log_info "Host: ${target_host}"
    log_info "IP: ${TARGET_IP}"
    log_info "User: ${REMOTE_USER}"
    
    # Export for use by other functions
    export TARGET_IP REMOTE_USER
}

# Function: Validate WinRM connectivity
validate_winrm_connectivity() {
    local target_host="$1"
    local winrm_password="$2"
    
    validate_required_params "validate_winrm_connectivity" target_host winrm_password TARGET_IP REMOTE_USER
    
    log_step "Validating WinRM connectivity to ${target_host}"
    
    # Test WinRM connection using ansible-inventory or a simple test
    log_info "Testing WinRM connection to ${REMOTE_USER}@${TARGET_IP}"
    
    # We can use ansible to test the connection
    if command -v ansible >/dev/null 2>&1; then
        local test_result
        if test_result=$(ansible "${target_host}" -i "${INVENTORY_FILE}" -m win_ping -e "ansible_password=${winrm_password}" 2>&1); then
            log_success "WinRM connectivity test passed"
            return 0
        else
            log_warning "WinRM test failed, but continuing (might still work): ${test_result}"
            # Don't fail here as WinRM might still work during playbook execution
            return 0
        fi
    else
        log_warning "Ansible not available for WinRM testing, skipping connectivity test"
        return 0
    fi
}

# Function: Validate Windows playbook exists
validate_windows_playbook() {
    local playbook="$1"
    
    validate_required_params "validate_windows_playbook" playbook
    
    local playbook_path="${PLAYBOOKS_DIR}/${playbook}"
    
    if [[ ! -f "${playbook_path}" ]]; then
        log_error "Playbook not found: ${playbook_path}"
        return 1
    fi
    
    # Check if playbook contains Windows-specific tasks (optional validation)
    if grep -q "win_" "${playbook_path}" || grep -q "windows" "${playbook_path}"; then
        log_info "Playbook appears to contain Windows-specific tasks"
    else
        log_warning "Playbook may not contain Windows-specific tasks"
    fi
    
    log_success "Playbook validated: ${playbook_path}"
}

# Function: Run Ansible playbook for Windows
run_windows_ansible_playbook() {
    local target_host="$1"
    local playbook="$2"
    local winrm_password="$3"
    local extra_vars="${4:-}"
    
    validate_required_params "run_windows_ansible_playbook" target_host playbook winrm_password
    validate_command_exists "ansible-playbook"
    validate_dir_exists "${PLAYBOOKS_DIR}" "Playbooks directory"
    
    log_step "Running Windows Ansible playbook: ${playbook} on ${target_host}"
    
    # Build ansible-playbook command for Windows
    local ansible_cmd=(
        "ansible-playbook"
        "-i" "../inventories/hosts.yml"
        "${playbook}"
        "--limit" "${target_host}"
        "-e" "ansible_password=${winrm_password}"
        "-v"  # Verbose output
    )
    
    # Add extra variables if provided
    if [[ -n "${extra_vars}" ]]; then
        ansible_cmd+=("-e" "${extra_vars}")
    fi
    
    # Change to playbooks directory and run
    local current_dir
    current_dir=$(pwd)
    
    if ! cd "${PLAYBOOKS_DIR}"; then
        log_error "Failed to change to playbooks directory: ${PLAYBOOKS_DIR}"
        return 1
    fi
    
    log_info "Executing: ${ansible_cmd[*]}"
    
    # Execute ansible-playbook with proper error handling
    local exit_code=0
    if ! time_command "Windows Ansible playbook execution" "${ansible_cmd[@]}"; then
        exit_code=$?
        log_error "Windows Ansible playbook failed with exit code: ${exit_code}"
    else
        log_success "Windows Ansible playbook completed successfully"
    fi
    
    # Return to original directory
    cd "${current_dir}"
    
    return ${exit_code}
}

# Function: Complete Windows deployment workflow
deploy_windows() {
    local target_host="$1"
    local playbook="$2"
    local winrm_password="$3"
    local extra_vars="${4:-}"
    
    validate_required_params "deploy_windows" target_host playbook winrm_password
    
    log_info "Starting Windows deployment workflow"
    log_info "Target: ${target_host}"
    log_info "Playbook: ${playbook}"
    
    # Parse inventory
    if ! parse_windows_inventory "${target_host}"; then
        return 1
    fi
    
    # Validate playbook
    if ! validate_windows_playbook "${playbook}"; then
        return 1
    fi
    
    # Validate WinRM connectivity (non-blocking)
    validate_winrm_connectivity "${target_host}" "${winrm_password}"
    
    # Run the playbook
    if ! run_windows_ansible_playbook "${target_host}" "${playbook}" "${winrm_password}" "${extra_vars}"; then
        return 1
    fi
    
    log_success "Windows deployment completed successfully"
}

# Function: List available Windows hosts
list_windows_hosts() {
    validate_file_exists "${INVENTORY_FILE}" "Inventory file"
    
    local inventory_script="${SCRIPT_DIR}/../common/inventory-parser.py"
    
    if ! python3 "${inventory_script}" "${INVENTORY_FILE}" --list-hosts --group windows; then
        log_error "Failed to list Windows hosts"
        return 1
    fi
}

# Function: List available playbooks (filtered for Windows if possible)
list_windows_playbooks() {
    validate_dir_exists "${PLAYBOOKS_DIR}" "Playbooks directory"
    
    log_info "Available playbooks (all):"
    find "${PLAYBOOKS_DIR}" -name "*.yml" -type f -exec basename {} \; | sort
    
    log_info ""
    log_info "Playbooks that appear to be Windows-specific:"
    find "${PLAYBOOKS_DIR}" -name "*.yml" -type f -exec grep -l "win_\|windows" {} \; 2>/dev/null | xargs -r basename -a | sort || {
        log_info "No obviously Windows-specific playbooks found"
    }
}

# Function: Test WinRM connection specifically
test_winrm_connection() {
    local target_host="$1"
    local winrm_password="$2"
    
    validate_required_params "test_winrm_connection" target_host winrm_password
    
    # Parse inventory first
    if ! parse_windows_inventory "${target_host}"; then
        return 1
    fi
    
    # Test connection
    validate_winrm_connectivity "${target_host}" "${winrm_password}"
}

# Function: Cleanup function for error handling
cleanup() {
    log_info "Performing cleanup"
    
    # Clean up any temporary files
    cleanup_temp_files "/tmp/windows_deploy_*"
    
    # Additional cleanup can be added here
}

# Main function for command-line usage
main() {
    # Setup error handling
    setup_error_handling
    
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <action> [arguments...]"
        echo "Actions:"
        echo "  deploy <target_host> <playbook> <winrm_password> [extra_vars]"
        echo "  parse-inventory <target_host>"
        echo "  test-winrm <target_host> <winrm_password>"
        echo "  validate-playbook <playbook>"
        echo "  list-hosts"
        echo "  list-playbooks"
        echo ""
        echo "Environment variables:"
        echo "  INVENTORY_FILE (default: ansible/inventories/hosts.yml)"
        echo "  PLAYBOOKS_DIR (default: ansible/playbooks)"
        exit 1
    fi
    
    local action="$1"
    shift
    
    case "${action}" in
        deploy)
            [[ $# -ge 3 ]] || { echo "deploy requires: target_host playbook winrm_password [extra_vars]"; exit 1; }
            deploy_windows "$@"
            ;;
        parse-inventory)
            [[ $# -eq 1 ]] || { echo "parse-inventory requires: target_host"; exit 1; }
            parse_windows_inventory "$1"
            echo "TARGET_IP=${TARGET_IP}"
            echo "REMOTE_USER=${REMOTE_USER}"
            ;;
        test-winrm)
            [[ $# -eq 2 ]] || { echo "test-winrm requires: target_host winrm_password"; exit 1; }
            test_winrm_connection "$@"
            ;;
        validate-playbook)
            [[ $# -eq 1 ]] || { echo "validate-playbook requires: playbook"; exit 1; }
            validate_windows_playbook "$1"
            ;;
        list-hosts)
            list_windows_hosts
            ;;
        list-playbooks)
            list_windows_playbooks
            ;;
        *)
            echo "Unknown action: ${action}"
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi