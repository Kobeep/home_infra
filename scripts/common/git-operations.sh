#!/usr/bin/env bash
#
# Git Operations Script
# Handles Git operations like commit, push, and authentication.
#

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./utils.sh
source "${SCRIPT_DIR}/utils.sh"

# Function: Setup git configuration
setup_git_config() {
    local user_email="${1:-jenkins@localhost}"
    local user_name="${2:-Jenkins CI}"
    
    log_info "Setting up Git configuration"
    git config user.email "${user_email}"
    git config user.name "${user_name}"
    log_success "Git configuration set: ${user_name} <${user_email}>"
}

# Function: Setup authenticated remote URL
setup_authenticated_remote() {
    local git_user="$1"
    local git_pass="$2"
    local remote_name="${3:-origin}"
    
    validate_required_params "setup_authenticated_remote" git_user git_pass
    
    log_info "Setting up authenticated Git remote"
    
    # Get current remote URL
    local orig_url
    if ! orig_url=$(git remote get-url "${remote_name}" 2>/dev/null); then
        log_error "Remote '${remote_name}' not found"
        return 1
    fi
    
    # Create authenticated URL
    local auth_url
    if [[ "${orig_url}" =~ ^https:// ]]; then
        auth_url=$(echo "${orig_url}" | sed -e "s#https://#https://${git_user}:${git_pass}@#")
    else
        log_error "Only HTTPS remotes are supported for authentication"
        return 1
    fi
    
    # Set the authenticated URL
    git remote set-url "${remote_name}" "${auth_url}"
    log_success "Authenticated remote URL configured"
}

# Function: Restore original remote URL (cleanup)
restore_original_remote() {
    local original_url="$1"
    local remote_name="${2:-origin}"
    
    if [[ -n "${original_url}" ]]; then
        log_info "Restoring original remote URL"
        git remote set-url "${remote_name}" "${original_url}"
        log_success "Original remote URL restored"
    fi
}

# Function: Check if there are changes to commit
has_changes() {
    ! git diff --cached --quiet
}

# Function: Add files to git
add_files() {
    local files=("$@")
    
    if [[ ${#files[@]} -eq 0 ]]; then
        log_error "No files specified to add"
        return 1
    fi
    
    log_info "Adding files to Git: ${files[*]}"
    
    for file in "${files[@]}"; do
        if [[ -e "${file}" ]]; then
            git add "${file}"
        else
            log_warning "File/directory not found, skipping: ${file}"
        fi
    done
    
    log_success "Files added to Git staging area"
}

# Function: Commit changes
commit_changes() {
    local commit_message="$1"
    local allow_empty="${2:-false}"
    
    validate_required_params "commit_changes" commit_message
    
    if ! has_changes && [[ "${allow_empty}" != "true" ]]; then
        log_info "No changes to commit"
        return 0
    fi
    
    log_info "Committing changes"
    
    if [[ "${allow_empty}" == "true" ]]; then
        git commit --allow-empty -m "${commit_message}"
    else
        git commit -m "${commit_message}"
    fi
    
    log_success "Changes committed: ${commit_message}"
}

# Function: Push changes
push_changes() {
    local remote_name="${1:-origin}"
    local branch_name="${2:-HEAD:main}"
    
    log_info "Pushing changes to ${remote_name} ${branch_name}"
    
    if git push "${remote_name}" "${branch_name}"; then
        log_success "Changes pushed successfully"
    else
        log_error "Failed to push changes"
        return 1
    fi
}

# Function: Complete git workflow (add, commit, push)
git_workflow() {
    local commit_message="$1"
    local git_user="$2"
    local git_pass="$3"
    shift 3
    local files_to_add=("$@")
    
    validate_required_params "git_workflow" commit_message git_user git_pass
    
    # Store original remote URL for cleanup
    local original_url
    original_url=$(git remote get-url origin 2>/dev/null || echo "")
    
    # Setup cleanup trap
    cleanup() {
        if [[ -n "${original_url}" ]]; then
            restore_original_remote "${original_url}"
        fi
    }
    trap cleanup EXIT
    
    # Setup Git
    setup_git_config
    setup_authenticated_remote "${git_user}" "${git_pass}"
    
    # Add files if specified
    if [[ ${#files_to_add[@]} -gt 0 ]]; then
        add_files "${files_to_add[@]}"
    fi
    
    # Check if there are changes
    if has_changes; then
        commit_changes "${commit_message}"
        push_changes
    else
        log_info "No changes to commit and push"
    fi
    
    # Cleanup happens automatically via trap
}

# Function: Check git repository status
check_git_status() {
    log_info "Checking Git repository status"
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a Git repository"
        return 1
    fi
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        log_warning "Repository has uncommitted changes"
        git status --porcelain
    else
        log_info "Repository is clean"
    fi
    
    # Check current branch
    local current_branch
    current_branch=$(git branch --show-current)
    log_info "Current branch: ${current_branch}"
    
    # Check remote tracking
    local upstream
    if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null); then
        log_info "Tracking upstream: ${upstream}"
    else
        log_warning "No upstream tracking branch configured"
    fi
}

# Function: Get timestamp for commit messages
get_timestamp() {
    local format="${1:-UTC}"
    
    case "${format}" in
        UTC)
            date -u +'%Y-%m-%d %H:%M:%S UTC'
            ;;
        local)
            date +'%Y-%m-%d %H:%M:%S %Z'
            ;;
        iso)
            date -u +'%Y-%m-%dT%H:%M:%SZ'
            ;;
        *)
            log_error "Unknown timestamp format: ${format}"
            return 1
            ;;
    esac
}

# Main function for command-line usage
main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <action> [arguments...]"
        echo "Actions:"
        echo "  setup-config [email] [name]"
        echo "  setup-auth <user> <pass> [remote]"
        echo "  add <file1> [file2] ..."
        echo "  commit <message> [allow-empty]"
        echo "  push [remote] [branch]"
        echo "  workflow <message> <user> <pass> [files...]"
        echo "  status"
        echo "  timestamp [format]"
        exit 1
    fi
    
    local action="$1"
    shift
    
    case "${action}" in
        setup-config)
            setup_git_config "$@"
            ;;
        setup-auth)
            [[ $# -ge 2 ]] || { echo "setup-auth requires: user pass [remote]"; exit 1; }
            setup_authenticated_remote "$@"
            ;;
        add)
            [[ $# -ge 1 ]] || { echo "add requires at least one file"; exit 1; }
            add_files "$@"
            ;;
        commit)
            [[ $# -ge 1 ]] || { echo "commit requires: message [allow-empty]"; exit 1; }
            commit_changes "$@"
            ;;
        push)
            push_changes "$@"
            ;;
        workflow)
            [[ $# -ge 3 ]] || { echo "workflow requires: message user pass [files...]"; exit 1; }
            git_workflow "$@"
            ;;
        status)
            check_git_status
            ;;
        timestamp)
            get_timestamp "$@"
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