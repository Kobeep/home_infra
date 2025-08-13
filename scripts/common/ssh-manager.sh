#!/usr/bin/env bash
#
# SSH Key Management Script
# Handles SSH key generation, validation, and deployment for remote hosts.
#

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "${SCRIPT_DIR}/utils.sh"

# Configuration with defaults
SSH_BASE_DIR="${SSH_BASE_DIR:-/var/jenkins_home/.ssh}"
SSH_KEY_TYPE="${SSH_KEY_TYPE:-rsa}"
SSH_KEY_BITS="${SSH_KEY_BITS:-4096}"

# Function: Generate SSH key pair
generate_ssh_key() {
    local host_name="$1"
    local key_path="${SSH_BASE_DIR}/${host_name}/id_rsa"
    local pub_key_path="${key_path}.pub"
    
    log_info "Generating SSH key for host: ${host_name}"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "${key_path}")"
    
    # Generate key pair
    ssh-keygen -t "${SSH_KEY_TYPE}" -b "${SSH_KEY_BITS}" -f "${key_path}" -N '' -q
    
    # Set proper permissions
    chmod 600 "${key_path}"
    chmod 644 "${pub_key_path}"
    
    log_success "SSH key generated: ${key_path}"
}

# Function: Check if SSH key exists
ssh_key_exists() {
    local host_name="$1"
    local key_path="${SSH_BASE_DIR}/${host_name}/id_rsa"
    
    [[ -f "${key_path}" ]] && [[ -f "${key_path}.pub" ]]
}

# Function: Deploy public key to remote host
deploy_public_key() {
    local host_name="$1"
    local target_ip="$2"
    local remote_user="$3"
    local ssh_password="$4"
    
    local key_path="${SSH_BASE_DIR}/${host_name}/id_rsa"
    local pub_key_path="${key_path}.pub"
    
    if [[ ! -f "${pub_key_path}" ]]; then
        log_error "Public key not found: ${pub_key_path}"
        return 1
    fi
    
    log_info "Deploying public key to ${remote_user}@${target_ip}"
    
    # Use sshpass to copy the public key
    if command -v sshpass >/dev/null 2>&1; then
        sshpass -p "${ssh_password}" ssh-copy-id -i "${pub_key_path}" \
            -o StrictHostKeyChecking=no \
            "${remote_user}@${target_ip}" 2>/dev/null || {
            log_warning "ssh-copy-id failed, this might be expected if key already exists"
            return 0
        }
    else
        log_error "sshpass not available for key deployment"
        return 1
    fi
    
    log_success "Public key deployed successfully"
}

# Function: Test SSH connection
test_ssh_connection() {
    local host_name="$1"
    local target_ip="$2"
    local remote_user="$3"
    
    local key_path="${SSH_BASE_DIR}/${host_name}/id_rsa"
    
    if [[ ! -f "${key_path}" ]]; then
        log_error "Private key not found: ${key_path}"
        return 1
    fi
    
    log_info "Testing SSH connection to ${remote_user}@${target_ip}"
    
    # Test SSH connection
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
           -i "${key_path}" "${remote_user}@${target_ip}" 'echo "SSH connection successful"' >/dev/null 2>&1; then
        log_success "SSH connection test passed"
        return 0
    else
        log_error "SSH connection test failed"
        return 1
    fi
}

# Function: Ensure SSH key is ready (generate if needed, deploy if needed)
ensure_ssh_key() {
    local host_name="$1"
    local target_ip="$2"
    local remote_user="$3"
    local ssh_password="$4"
    
    validate_required_params "ensure_ssh_key" host_name target_ip remote_user ssh_password
    
    local key_path="${SSH_BASE_DIR}/${host_name}/id_rsa"
    
    # Generate key if it doesn't exist
    if ! ssh_key_exists "${host_name}"; then
        generate_ssh_key "${host_name}"
        
        # Deploy the new key
        if ! deploy_public_key "${host_name}" "${target_ip}" "${remote_user}" "${ssh_password}"; then
            log_error "Failed to deploy public key"
            return 1
        fi
    else
        log_info "SSH key already exists: ${key_path}"
        # Ensure proper permissions
        chmod 600 "${key_path}"
    fi
    
    # Test the connection
    if ! test_ssh_connection "${host_name}" "${target_ip}" "${remote_user}"; then
        log_warning "SSH connection failed, removing key and retrying..."
        rm -rf "$(dirname "${key_path}")"
        
        # Regenerate and redeploy
        generate_ssh_key "${host_name}"
        if ! deploy_public_key "${host_name}" "${target_ip}" "${remote_user}" "${ssh_password}"; then
            log_error "Failed to deploy public key on retry"
            return 1
        fi
        
        # Test again
        if ! test_ssh_connection "${host_name}" "${target_ip}" "${remote_user}"; then
            log_error "SSH connection still failing after regeneration"
            return 1
        fi
    fi
    
    log_success "SSH key is ready for ${host_name}"
    echo "${key_path}"  # Return the key path for use by caller
}

# Function: Clean up SSH keys for a host
cleanup_ssh_key() {
    local host_name="$1"
    local key_dir="${SSH_BASE_DIR}/${host_name}"
    
    if [[ -d "${key_dir}" ]]; then
        log_info "Cleaning up SSH keys for ${host_name}"
        rm -rf "${key_dir}"
        log_success "SSH keys cleaned up"
    else
        log_info "No SSH keys found for ${host_name}"
    fi
}

# Main function for command-line usage
main() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <action> <host_name> [target_ip] [remote_user] [ssh_password]"
        echo "Actions:"
        echo "  generate <host_name>"
        echo "  exists <host_name>"
        echo "  deploy <host_name> <target_ip> <remote_user> <ssh_password>"
        echo "  test <host_name> <target_ip> <remote_user>"
        echo "  ensure <host_name> <target_ip> <remote_user> <ssh_password>"
        echo "  cleanup <host_name>"
        exit 1
    fi
    
    local action="$1"
    local host_name="$2"
    
    case "${action}" in
        generate)
            generate_ssh_key "${host_name}"
            ;;
        exists)
            if ssh_key_exists "${host_name}"; then
                echo "yes"
                exit 0
            else
                echo "no"
                exit 1
            fi
            ;;
        deploy)
            [[ $# -eq 5 ]] || { echo "deploy requires: host_name target_ip remote_user ssh_password"; exit 1; }
            deploy_public_key "${host_name}" "$3" "$4" "$5"
            ;;
        test)
            [[ $# -eq 4 ]] || { echo "test requires: host_name target_ip remote_user"; exit 1; }
            test_ssh_connection "${host_name}" "$3" "$4"
            ;;
        ensure)
            [[ $# -eq 5 ]] || { echo "ensure requires: host_name target_ip remote_user ssh_password"; exit 1; }
            ensure_ssh_key "${host_name}" "$3" "$4" "$5"
            ;;
        cleanup)
            cleanup_ssh_key "${host_name}"
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