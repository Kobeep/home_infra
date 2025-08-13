#!/usr/bin/env bash
#
# Jenkins Backup Script
# Handles Jenkins pipeline backup operations.
#

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

# Configuration with defaults
JENKINS_HOME="${JENKINS_HOME:-/var/jenkins_home}"
JENKINS_BACKUP_DIR="${JENKINS_BACKUP_DIR:-jenkins-pipelines-backup}"

# Function: Backup Jenkins pipeline configurations
backup_jenkins_pipelines() {
    local backup_dir="$1"
    
    validate_required_params "backup_jenkins_pipelines" backup_dir
    validate_dir_exists "${JENKINS_HOME}" "Jenkins home directory"
    
    log_step "Backing up Jenkins pipeline configurations"
    
    # Clean and recreate backup directory
    if [[ -d "${backup_dir}" ]]; then
        log_info "Removing existing backup directory: ${backup_dir}"
        rm -rf "${backup_dir}"
    fi
    
    create_directory "${backup_dir}"
    
    # Backup jobs directory, excluding build logs
    local jobs_dir="${JENKINS_HOME}/jobs"
    
    if [[ ! -d "${jobs_dir}" ]]; then
        log_warning "Jenkins jobs directory not found: ${jobs_dir}"
        return 0
    fi
    
    log_info "Creating tar archive of Jenkins jobs (excluding builds)"
    
    # Use tar to copy jobs while excluding builds directory
    if tar cf - \
        --exclude='jobs/*/builds' \
        --exclude='jobs/*/workspace' \
        --exclude='jobs/*/lastStable' \
        --exclude='jobs/*/lastSuccessful' \
        --exclude='jobs/*/lastFailed' \
        --exclude='jobs/*/lastUnstable' \
        --exclude='jobs/*/lastUnsuccessful' \
        -C "${JENKINS_HOME}" jobs \
    | tar xf - -C "${backup_dir}"; then
        log_success "Jenkins pipeline backup completed"
    else
        log_error "Failed to backup Jenkins pipelines"
        return 1
    fi
    
    # Show backup summary
    local job_count
    job_count=$(find "${backup_dir}/jobs" -maxdepth 1 -type d ! -name jobs | wc -l)
    log_info "Backed up ${job_count} Jenkins jobs to ${backup_dir}"
}

# Function: Backup Jenkins system configuration
backup_jenkins_system_config() {
    local backup_dir="$1"
    
    validate_required_params "backup_jenkins_system_config" backup_dir
    validate_dir_exists "${JENKINS_HOME}" "Jenkins home directory"
    
    log_step "Backing up Jenkins system configuration"
    
    local config_backup_dir="${backup_dir}/system-config"
    create_directory "${config_backup_dir}"
    
    # List of important Jenkins configuration files
    local config_files=(
        "config.xml"
        "credentials.xml"
        "jenkins.model.JenkinsLocationConfiguration.xml"
        "org.jenkinsci.plugins.workflow.libs.GlobalLibraries.xml"
        "scriptApproval.xml"
    )
    
    # Backup each configuration file if it exists
    for config_file in "${config_files[@]}"; do
        local source_file="${JENKINS_HOME}/${config_file}"
        if [[ -f "${source_file}" ]]; then
            log_info "Backing up: ${config_file}"
            cp "${source_file}" "${config_backup_dir}/"
        else
            log_warning "Configuration file not found: ${config_file}"
        fi
    done
    
    # Backup plugins list
    if [[ -d "${JENKINS_HOME}/plugins" ]]; then
        log_info "Creating plugins list"
        find "${JENKINS_HOME}/plugins" -name "*.jpi" -exec basename {} .jpi \; | sort > "${config_backup_dir}/plugins-list.txt"
    fi
    
    log_success "Jenkins system configuration backup completed"
}

# Function: Clean old backups
clean_old_backups() {
    local backup_base_dir="$1"
    local retention_days="${2:-7}"
    
    validate_required_params "clean_old_backups" backup_base_dir
    
    log_step "Cleaning old backup directories older than ${retention_days} days"
    
    if [[ ! -d "${backup_base_dir}" ]]; then
        log_info "Backup base directory does not exist: ${backup_base_dir}"
        return 0
    fi
    
    # Find and remove old backup directories
    local old_backups
    if old_backups=$(find "${backup_base_dir}" -maxdepth 1 -type d -name "*backup*" -mtime +${retention_days} 2>/dev/null); then
        if [[ -n "${old_backups}" ]]; then
            echo "${old_backups}" | while read -r old_backup; do
                log_info "Removing old backup: ${old_backup}"
                rm -rf "${old_backup}"
            done
            log_success "Old backups cleaned up"
        else
            log_info "No old backups found to clean up"
        fi
    else
        log_info "No backup directories found for cleanup"
    fi
}

# Function: Validate backup integrity
validate_backup() {
    local backup_dir="$1"
    
    validate_required_params "validate_backup" backup_dir
    validate_dir_exists "${backup_dir}" "Backup directory"
    
    log_step "Validating backup integrity"
    
    local jobs_dir="${backup_dir}/jobs"
    
    if [[ ! -d "${jobs_dir}" ]]; then
        log_error "Jobs directory not found in backup: ${jobs_dir}"
        return 1
    fi
    
    # Check if any jobs were backed up
    local job_count
    job_count=$(find "${jobs_dir}" -maxdepth 1 -type d ! -name jobs | wc -l)
    
    if [[ ${job_count} -eq 0 ]]; then
        log_warning "No Jenkins jobs found in backup"
    else
        log_success "Backup validation passed: ${job_count} jobs found"
    fi
    
    # Check for config.xml files in jobs
    local config_count
    config_count=$(find "${jobs_dir}" -name "config.xml" | wc -l)
    log_info "Found ${config_count} job configuration files"
    
    return 0
}

# Function: Complete backup workflow
complete_backup() {
    local backup_dir="${1:-${JENKINS_BACKUP_DIR}}"
    local include_system_config="${2:-false}"
    local clean_old="${3:-false}"
    local retention_days="${4:-7}"
    
    log_info "Starting complete Jenkins backup workflow"
    
    # Backup Jenkins pipelines
    if ! backup_jenkins_pipelines "${backup_dir}"; then
        return 1
    fi
    
    # Backup system configuration if requested
    if [[ "${include_system_config}" == "true" ]]; then
        backup_jenkins_system_config "${backup_dir}"
    fi
    
    # Validate backup
    if ! validate_backup "${backup_dir}"; then
        log_error "Backup validation failed"
        return 1
    fi
    
    # Clean old backups if requested
    if [[ "${clean_old}" == "true" ]]; then
        clean_old_backups "$(dirname "${backup_dir}")" "${retention_days}"
    fi
    
    log_success "Complete Jenkins backup workflow finished"
}

# Function: Cleanup function for error handling
cleanup() {
    log_info "Performing backup cleanup"
    
    # Clean up any temporary files
    cleanup_temp_files "/tmp/jenkins_backup_*"
}

# Main function for command-line usage
main() {
    # Setup error handling
    setup_error_handling
    
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <action> [arguments...]"
        echo "Actions:"
        echo "  backup-pipelines <backup_dir>"
        echo "  backup-system-config <backup_dir>"
        echo "  validate-backup <backup_dir>"
        echo "  clean-old-backups <backup_base_dir> [retention_days]"
        echo "  complete-backup [backup_dir] [include_system_config] [clean_old] [retention_days]"
        echo ""
        echo "Environment variables:"
        echo "  JENKINS_HOME (default: /var/jenkins_home)"
        echo "  JENKINS_BACKUP_DIR (default: jenkins-pipelines-backup)"
        echo ""
        echo "Examples:"
        echo "  $0 backup-pipelines my-backup"
        echo "  $0 complete-backup jenkins-backup true true 7"
        exit 1
    fi
    
    local action="$1"
    shift
    
    case "${action}" in
        backup-pipelines)
            [[ $# -eq 1 ]] || { echo "backup-pipelines requires: backup_dir"; exit 1; }
            backup_jenkins_pipelines "$1"
            ;;
        backup-system-config)
            [[ $# -eq 1 ]] || { echo "backup-system-config requires: backup_dir"; exit 1; }
            backup_jenkins_system_config "$1"
            ;;
        validate-backup)
            [[ $# -eq 1 ]] || { echo "validate-backup requires: backup_dir"; exit 1; }
            validate_backup "$1"
            ;;
        clean-old-backups)
            [[ $# -ge 1 ]] || { echo "clean-old-backups requires: backup_base_dir [retention_days]"; exit 1; }
            clean_old_backups "$@"
            ;;
        complete-backup)
            complete_backup "$@"
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