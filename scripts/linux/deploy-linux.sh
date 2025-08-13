#!/usr/bin/env bash
#
# Linux Deployment Script
# Handles the complete Linux deployment workflow using Ansible.
#

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

# Configuration with defaults
INVENTORY_FILE="${INVENTORY_FILE:-ansible/inventories/hosts.yml}"
PLAYBOOKS_DIR="${PLAYBOOKS_DIR:-ansible/playbooks}"
SSH_BASE_DIR="${SSH_BASE_DIR:-/var/jenkins_home/.ssh}"

# Function: Parse Linux inventory and extract host configuration
parse_linux_inventory() {
    local target_host="$1"
    
    validate_required_params "parse_linux_inventory" target_host
    validate_file_exists "${INVENTORY_FILE}" "Inventory file"
    validate_command_exists "python3"
    
    log_step "Parsing Linux inventory for host: ${target_host}"
    
    local inventory_script="${SCRIPT_DIR}/../common/inventory-parser.py"
    local host_config_json
    
    if ! host_config_json=$(python3 "${inventory_script}" "${INVENTORY_FILE}" "${target_host}" --group linux); then
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

# Function: Ensure SSH connectivity
ensure_ssh_connectivity() {
    local target_host="$1"
    local ssh_password="$2"
    
    validate_required_params "ensure_ssh_connectivity" target_host ssh_password TARGET_IP REMOTE_USER
    
    log_step "Ensuring SSH connectivity to ${target_host}"
    
    local ssh_script="${SCRIPT_DIR}/../common/ssh-manager.sh"
    local private_key_path
    
    # Ensure SSH key is ready and get the key path
    if ! private_key_path=$(bash "${ssh_script}" ensure "${target_host}" "${TARGET_IP}" "${REMOTE_USER}" "${ssh_password}"); then
        log_error "Failed to ensure SSH connectivity"
        return 1
    fi
    
    log_success "SSH connectivity established"
    
    # Export key path for use by Ansible
    export PRIVATE_KEY_PATH="${private_key_path}"
}

# Function: Validate playbook exists
validate_playbook() {
    local playbook="$1"
    
    validate_required_params "validate_playbook" playbook
    
    local playbook_path="${PLAYBOOKS_DIR}/${playbook}"
    
    if [[ ! -f "${playbook_path}" ]]; then
        log_error "Playbook not found: ${playbook_path}"
        return 1
    fi
    
    log_info "Playbook validated: ${playbook_path}"
}

# Function: Run Ansible playbook
run_ansible_playbook() {
    local target_host="$1"
    local playbook="$2"
    local ssh_password="$3"
    local extra_vars="${4:-}"
    
    validate_required_params "run_ansible_playbook" target_host playbook ssh_password
    validate_command_exists "ansible-playbook"
    validate_command_exists "sshpass"
    validate_dir_exists "${PLAYBOOKS_DIR}" "Playbooks directory"
    
    log_step "Running Ansible playbook: ${playbook} on ${target_host}"
    
    # Build ansible-playbook command
    local ansible_cmd=(
        "sshpass" "-p" "${ssh_password}"
        "ansible-playbook"
        "-i" "../inventories/hosts.yml"
        "${playbook}"
        "-K"  # Ask for become password
        "--limit" "${target_host}"
        "-e" "hosts_to_deploy=${target_host}"
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
    if ! time_command "Ansible playbook execution" "${ansible_cmd[@]}"; then
        exit_code=$?
        log_error "Ansible playbook failed with exit code: ${exit_code}"
    else
        log_success "Ansible playbook completed successfully"
    fi
    
    # Return to original directory
    cd "${current_dir}"
    
    return ${exit_code}
}

# Function: Complete Linux deployment workflow
deploy_linux() {
    local target_host="$1"
    local playbook="$2"
    local ssh_password="$3"
    local extra_vars="${4:-}"
    
    validate_required_params "deploy_linux" target_host playbook ssh_password
    
    log_info "Starting Linux deployment workflow"
    log_info "Target: ${target_host}"
    log_info "Playbook: ${playbook}"
    
    # Parse inventory
    if ! parse_linux_inventory "${target_host}"; then
        return 1
    fi
    
    # Validate playbook
    if ! validate_playbook "${playbook}"; then
        return 1
    fi
    
    # Ensure SSH connectivity
    if ! ensure_ssh_connectivity "${target_host}" "${ssh_password}"; then
        return 1
    fi
    
    # Run the playbook
    if ! run_ansible_playbook "${target_host}" "${playbook}" "${ssh_password}" "${extra_vars}"; then
        return 1
    fi
    
    log_success "Linux deployment completed successfully"
}

# Function: List available Linux hosts
list_linux_hosts() {
    validate_file_exists "${INVENTORY_FILE}" "Inventory file"
    
    local inventory_script="${SCRIPT_DIR}/../common/inventory-parser.py"
    
    if ! python3 "${inventory_script}" "${INVENTORY_FILE}" --list-hosts --group linux; then
        log_error "Failed to list Linux hosts"
        return 1
    fi
}

# Function: List available playbooks
list_playbooks() {
    validate_dir_exists "${PLAYBOOKS_DIR}" "Playbooks directory"
    
    log_info "Available playbooks:"
    find "${PLAYBOOKS_DIR}" -name "*.yml" -type f -exec basename {} \; | sort
}

# Function: Cleanup function for error handling
cleanup() {
    log_info "Performing cleanup"
    
    # Clean up any temporary files
    cleanup_temp_files "/tmp/linux_deploy_*"
    
    # Additional cleanup can be added here
}

# Main function for command-line usage
main() {
    # Setup error handling
    setup_error_handling
    
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <action> [arguments...]"
        echo "Actions:"
        echo "  deploy <target_host> <playbook> <ssh_password> [extra_vars]"
        echo "  parse-inventory <target_host>"
        echo "  test-ssh <target_host> <ssh_password>"
        echo "  validate-playbook <playbook>"
        echo "  list-hosts"
        echo "  list-playbooks"
        echo ""
        echo "Environment variables:"
        echo "  INVENTORY_FILE (default: ansible/inventories/hosts.yml)"
        echo "  PLAYBOOKS_DIR (default: ansible/playbooks)"
        echo "  SSH_BASE_DIR (default: /var/jenkins_home/.ssh)"
        exit 1
    fi
    
    local action="$1"
    shift
    
    case "${action}" in
        deploy)
            [[ $# -ge 3 ]] || { echo "deploy requires: target_host playbook ssh_password [extra_vars]"; exit 1; }
            deploy_linux "$@"
            ;;
        parse-inventory)
            [[ $# -eq 1 ]] || { echo "parse-inventory requires: target_host"; exit 1; }
            parse_linux_inventory "$1"
            echo "TARGET_IP=${TARGET_IP}"
            echo "REMOTE_USER=${REMOTE_USER}"
            ;;
        test-ssh)
            [[ $# -eq 2 ]] || { echo "test-ssh requires: target_host ssh_password"; exit 1; }
            parse_linux_inventory "$1"
            ensure_ssh_connectivity "$1" "$2"
            ;;
        validate-playbook)
            [[ $# -eq 1 ]] || { echo "validate-playbook requires: playbook"; exit 1; }
            validate_playbook "$1"
            ;;
        list-hosts)
            list_linux_hosts
            ;;
        list-playbooks)
            list_playbooks
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