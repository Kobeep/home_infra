#!/usr/bin/env bash
#
# Common Utilities
# Shared functions and utilities for pipeline scripts.
#

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  INFO: $*${NC}" >&2
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS: $*${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $*${NC}" >&2
}

log_error() {
    echo -e "${RED}❌ ERROR: $*${NC}" >&2
}

log_step() {
    echo -e "${BLUE}📋 STEP: $*${NC}" >&2
}

# Validation functions
validate_file_exists() {
    local file="$1"
    local description="${2:-File}"
    
    if [[ ! -f "${file}" ]]; then
        log_error "${description} not found: ${file}"
        return 1
    fi
}

validate_dir_exists() {
    local dir="$1"
    local description="${2:-Directory}"
    
    if [[ ! -d "${dir}" ]]; then
        log_error "${description} not found: ${dir}"
        return 1
    fi
}

validate_command_exists() {
    local cmd="$1"
    
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        log_error "Required command not found: ${cmd}"
        return 1
    fi
}

validate_required_params() {
    local func_name="$1"
    shift
    
    for param_name in "$@"; do
        local param_value="${!param_name:-}"
        if [[ -z "${param_value}" ]]; then
            log_error "Required parameter '${param_name}' is empty in function '${func_name}'"
            return 1
        fi
    done
}

# Environment validation
validate_environment() {
    local required_vars=("$@")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("${var}")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
}

# File operations
backup_file() {
    local file="$1"
    local backup_suffix="${2:-.backup.$(date +%Y%m%d_%H%M%S)}"
    
    if [[ -f "${file}" ]]; then
        local backup_file="${file}${backup_suffix}"
        cp "${file}" "${backup_file}"
        log_info "Backed up ${file} to ${backup_file}"
    fi
}

create_directory() {
    local dir="$1"
    local mode="${2:-755}"
    
    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}"
        chmod "${mode}" "${dir}"
        log_info "Created directory: ${dir}"
    fi
}

# Process management
wait_for_process() {
    local pid="$1"
    local timeout="${2:-60}"
    local description="${3:-Process}"
    
    local count=0
    while kill -0 "${pid}" 2>/dev/null; do
        if [[ ${count} -ge ${timeout} ]]; then
            log_error "${description} did not complete within ${timeout} seconds"
            return 1
        fi
        sleep 1
        ((count++))
    done
    
    log_success "${description} completed"
}

# Network utilities
wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    local description="${4:-Service}"
    
    log_info "Waiting for ${description} at ${host}:${port}"
    
    local count=0
    while ! nc -z "${host}" "${port}" 2>/dev/null; do
        if [[ ${count} -ge ${timeout} ]]; then
            log_error "${description} not available at ${host}:${port} within ${timeout} seconds"
            return 1
        fi
        sleep 1
        ((count++))
    done
    
    log_success "${description} is available at ${host}:${port}"
}

# JSON utilities (if jq is available)
parse_json() {
    local json_string="$1"
    local jq_filter="$2"
    
    if command -v jq >/dev/null 2>&1; then
        echo "${json_string}" | jq -r "${jq_filter}"
    else
        log_error "jq command not available for JSON parsing"
        return 1
    fi
}

# Cleanup functions
cleanup_temp_files() {
    local temp_pattern="${1:-/tmp/pipeline_*}"
    
    log_info "Cleaning up temporary files matching: ${temp_pattern}"
    # Using find for safer cleanup
    find /tmp -name "$(basename "${temp_pattern}")" -type f -mtime +1 -delete 2>/dev/null || true
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number="${1:-unknown}"
    
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    
    # Call cleanup function if it exists
    if declare -f cleanup >/dev/null; then
        log_info "Running cleanup function"
        cleanup || true
    fi
    
    exit "${exit_code}"
}

# Setup error handling
setup_error_handling() {
    trap 'handle_error ${LINENO}' ERR
}

# Performance monitoring
time_command() {
    local description="$1"
    shift
    
    log_info "Starting: ${description}"
    local start_time=$(date +%s)
    
    "$@"
    local exit_code=$?
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ ${exit_code} -eq 0 ]]; then
        log_success "Completed: ${description} (${duration}s)"
    else
        log_error "Failed: ${description} (${duration}s)"
    fi
    
    return ${exit_code}
}

# Configuration helpers
load_config() {
    local config_file="$1"
    
    if [[ -f "${config_file}" ]]; then
        # shellcheck source=/dev/null
        source "${config_file}"
        log_info "Loaded configuration from: ${config_file}"
    else
        log_warning "Configuration file not found: ${config_file}"
    fi
}

# Export functions for use in other scripts
export -f log_info log_success log_warning log_error log_step
export -f validate_file_exists validate_dir_exists validate_command_exists validate_required_params
export -f validate_environment backup_file create_directory
export -f wait_for_process wait_for_port parse_json cleanup_temp_files
export -f handle_error setup_error_handling time_command load_config