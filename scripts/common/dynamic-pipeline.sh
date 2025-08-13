#!/usr/bin/env bash
#
# Dynamic Pipeline Helper Script
# Provides utility functions for dynamic host and playbook selection.
#

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

# Configuration with defaults
INVENTORY_FILE="${INVENTORY_FILE:-ansible/inventories/hosts.yml}"
PLAYBOOKS_DIR="${PLAYBOOKS_DIR:-ansible/playbooks}"

# Function: Get hosts for a specific group
get_hosts_for_group() {
    local target_group="$1"
    
    validate_required_params "get_hosts_for_group" target_group
    validate_file_exists "${INVENTORY_FILE}" "Inventory file"
    
    log_info "Getting hosts for group: ${target_group}"
    
    local inventory_script="${SCRIPT_DIR}/../common/inventory-parser.py"
    
    if ! python3 "${inventory_script}" "${INVENTORY_FILE}" --list-hosts --group "${target_group}"; then
        log_error "Failed to get hosts for group: ${target_group}"
        return 1
    fi
}

# Function: Get all available playbooks
get_available_playbooks() {
    validate_dir_exists "${PLAYBOOKS_DIR}" "Playbooks directory"
    
    log_info "Getting available playbooks from: ${PLAYBOOKS_DIR}"
    
    # Return JSON array of playbook names
    find "${PLAYBOOKS_DIR}" -name "*.yml" -type f -exec basename {} \; | sort | jq -R . | jq -s .
}

# Function: Validate group exists in inventory
validate_group_exists() {
    local target_group="$1"
    
    validate_required_params "validate_group_exists" target_group
    validate_file_exists "${INVENTORY_FILE}" "Inventory file"
    
    log_info "Validating group exists: ${target_group}"
    
    # Parse inventory and check if group exists
    if python3 -c "
import yaml, sys
with open('${INVENTORY_FILE}') as f:
    inv = yaml.safe_load(f)
groups = inv.get('all', {}).get('children', {})
if '${target_group}' in groups:
    print('true')
    sys.exit(0)
else:
    print('false')
    sys.exit(1)
" 2>/dev/null; then
        log_success "Group '${target_group}' exists in inventory"
        return 0
    else
        log_error "Group '${target_group}' not found in inventory"
        return 1
    fi
}

# Function: Get groups from inventory
get_available_groups() {
    validate_file_exists "${INVENTORY_FILE}" "Inventory file"
    
    log_info "Getting available groups from inventory"
    
    # Return JSON array of group names
    python3 -c "
import yaml, json
with open('${INVENTORY_FILE}') as f:
    inv = yaml.safe_load(f)
groups = list(inv.get('all', {}).get('children', {}).keys())
print(json.dumps(sorted(groups)))
"
}

# Function: Format hosts for Jenkins choice parameter
format_hosts_for_jenkins() {
    local hosts_json="$1"
    
    # Convert JSON array to newline-separated string for Jenkins
    echo "${hosts_json}" | jq -r '.[]' | tr '\n' '\n'
}

# Function: Format playbooks for Jenkins choice parameter
format_playbooks_for_jenkins() {
    local playbooks_json="$1"
    
    # Convert JSON array to newline-separated string for Jenkins
    echo "${playbooks_json}" | jq -r '.[]' | tr '\n' '\n'
}

# Function: Generate Jenkins input parameters script
generate_jenkins_input_script() {
    local target_group="$1"
    local output_file="${2:-/tmp/jenkins_input_params.groovy}"
    
    validate_required_params "generate_jenkins_input_script" target_group
    
    log_step "Generating Jenkins input parameters script for group: ${target_group}"
    
    # Get hosts and playbooks
    local hosts_json
    local playbooks_json
    
    if ! hosts_json=$(get_hosts_for_group "${target_group}"); then
        return 1
    fi
    
    if ! playbooks_json=$(get_available_playbooks); then
        return 1
    fi
    
    # Check if we have hosts
    local host_count
    host_count=$(echo "${hosts_json}" | jq 'length')
    
    if [[ ${host_count} -eq 0 ]]; then
        log_error "No hosts found for group: ${target_group}"
        return 1
    fi
    
    # Format for Jenkins choice parameters
    local hosts_formatted
    local playbooks_formatted
    
    hosts_formatted=$(echo "${hosts_json}" | jq -r '.[]' | paste -sd '\n' -)
    playbooks_formatted=$(echo "${playbooks_json}" | jq -r '.[]' | paste -sd '\n' -)
    
    # Generate the Groovy script for Jenkins input
    cat > "${output_file}" << EOF
[
    [
        \$class: 'ChoiceParameterDefinition',
        choices: '''${hosts_formatted}''',
        description: 'Choose the target host from the inventory',
        name: 'TARGET_HOST'
    ],
    [
        \$class: 'ChoiceParameterDefinition',
        choices: '''${playbooks_formatted}''',
        description: 'Choose the playbook to run',
        name: 'PLAYBOOK'
    ],
    password(name: 'AUTH_PASS', defaultValue: '', description: 'Enter the password for the target host (WinRM for Windows / SSH for Linux)')
]
EOF
    
    log_success "Jenkins input parameters script generated: ${output_file}"
    echo "${output_file}"
}

# Function: Cleanup function for error handling
cleanup() {
    log_info "Performing dynamic pipeline cleanup"
    
    # Clean up any temporary files
    cleanup_temp_files "/tmp/jenkins_input_*"
    cleanup_temp_files "/tmp/dynamic_pipeline_*"
}

# Main function for command-line usage
main() {
    # Setup error handling
    setup_error_handling
    
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <action> [arguments...]"
        echo "Actions:"
        echo "  get-hosts <group>                    # Get hosts for specific group"
        echo "  get-playbooks                       # Get all available playbooks"
        echo "  validate-group <group>              # Check if group exists"
        echo "  get-groups                          # Get all available groups"
        echo "  format-hosts-jenkins <hosts_json>   # Format hosts for Jenkins"
        echo "  format-playbooks-jenkins <pb_json>  # Format playbooks for Jenkins"
        echo "  generate-input-script <group> [output_file]  # Generate Jenkins input script"
        echo ""
        echo "Environment variables:"
        echo "  INVENTORY_FILE (default: ansible/inventories/hosts.yml)"
        echo "  PLAYBOOKS_DIR (default: ansible/playbooks)"
        exit 1
    fi
    
    local action="$1"
    shift
    
    case "${action}" in
        get-hosts)
            [[ $# -eq 1 ]] || { echo "get-hosts requires: group"; exit 1; }
            get_hosts_for_group "$1"
            ;;
        get-playbooks)
            get_available_playbooks
            ;;
        validate-group)
            [[ $# -eq 1 ]] || { echo "validate-group requires: group"; exit 1; }
            validate_group_exists "$1"
            ;;
        get-groups)
            get_available_groups
            ;;
        format-hosts-jenkins)
            [[ $# -eq 1 ]] || { echo "format-hosts-jenkins requires: hosts_json"; exit 1; }
            format_hosts_for_jenkins "$1"
            ;;
        format-playbooks-jenkins)
            [[ $# -eq 1 ]] || { echo "format-playbooks-jenkins requires: playbooks_json"; exit 1; }
            format_playbooks_for_jenkins "$1"
            ;;
        generate-input-script)
            [[ $# -ge 1 ]] || { echo "generate-input-script requires: group [output_file]"; exit 1; }
            generate_jenkins_input_script "$@"
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