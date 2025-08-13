#!/usr/bin/env bash
#
# Jenkins Node Management Script
# Handles Jenkins slave/agent node operations.
#

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/utils.sh
source "${SCRIPT_DIR}/../common/utils.sh"

# Configuration with defaults
JENKINS_URL="${JENKINS_URL:-http://192.168.0.122:8080/}"
AGENT_JAR_PATH="${AGENT_JAR_PATH:-agent.jar}"
AGENT_SECRET="${AGENT_SECRET:-}"
AGENT_NAME="${AGENT_NAME:-slave}"
AGENT_WORK_DIR="${AGENT_WORK_DIR:-/var/jenkins_home}"

# Function: Check if Jenkins node is online
is_node_online() {
    local node_name="$1"
    
    validate_required_params "is_node_online" node_name
    
    log_info "Checking if Jenkins node '${node_name}' is online"
    
    # This requires Jenkins CLI or we simulate by checking for running processes
    # In the original code, they check using Jenkins.instance which is Groovy
    # We'll use a process-based approach as a fallback
    
    if pgrep -f "name ${node_name}" >/dev/null 2>&1; then
        log_success "Node '${node_name}' appears to be running"
        return 0
    else
        log_info "Node '${node_name}' does not appear to be running"
        return 1
    fi
}

# Function: Start Jenkins agent
start_jenkins_agent() {
    local node_name="$1"
    local agent_secret="$2"
    local jenkins_url="${3:-${JENKINS_URL}}"
    local work_dir="${4:-${AGENT_WORK_DIR}}"
    local agent_jar="${5:-${AGENT_JAR_PATH}}"
    
    validate_required_params "start_jenkins_agent" node_name agent_secret
    validate_file_exists "${agent_jar}" "Jenkins agent JAR"
    validate_command_exists "java"
    
    log_step "Starting Jenkins agent: ${node_name}"
    
    # Prepare agent command
    local agent_cmd=(
        "java"
        "-jar" "${agent_jar}"
        "-url" "${jenkins_url}"
        "-secret" "${agent_secret}"
        "-name" "${node_name}"
        "-webSocket"
        "-workDir" "${work_dir}"
    )
    
    log_info "Agent command: ${agent_cmd[*]}"
    
    # Start agent in background
    log_info "Starting Jenkins agent in background"
    nohup "${agent_cmd[@]}" > "/tmp/jenkins-agent-${node_name}.log" 2>&1 &
    local agent_pid=$!
    
    # Store PID for later reference
    echo "${agent_pid}" > "/tmp/jenkins-agent-${node_name}.pid"
    
    log_success "Jenkins agent started with PID: ${agent_pid}"
    log_info "Agent log: /tmp/jenkins-agent-${node_name}.log"
    
    # Give it a moment to start
    sleep 2
    
    # Check if process is still running
    if kill -0 "${agent_pid}" 2>/dev/null; then
        log_success "Agent process is running"
    else
        log_error "Agent process failed to start or exited immediately"
        log_info "Check agent log for details: /tmp/jenkins-agent-${node_name}.log"
        return 1
    fi
}

# Function: Stop Jenkins agent
stop_jenkins_agent() {
    local node_name="$1"
    
    validate_required_params "stop_jenkins_agent" node_name
    
    log_step "Stopping Jenkins agent: ${node_name}"
    
    local pid_file="/tmp/jenkins-agent-${node_name}.pid"
    
    if [[ -f "${pid_file}" ]]; then
        local agent_pid
        agent_pid=$(cat "${pid_file}")
        
        if kill -0 "${agent_pid}" 2>/dev/null; then
            log_info "Stopping agent with PID: ${agent_pid}"
            kill "${agent_pid}"
            
            # Wait for process to stop
            if wait_for_process "${agent_pid}" 30 "Jenkins agent stop"; then
                log_success "Jenkins agent stopped successfully"
            else
                log_warning "Agent did not stop gracefully, forcing termination"
                kill -9 "${agent_pid}" 2>/dev/null || true
            fi
        else
            log_info "Agent process not running (PID: ${agent_pid})"
        fi
        
        rm -f "${pid_file}"
    else
        log_info "No PID file found, trying to stop by process name"
        if pkill -f "name ${node_name}"; then
            log_success "Stopped agent processes by name"
        else
            log_info "No agent processes found to stop"
        fi
    fi
}

# Function: Restart Jenkins agent
restart_jenkins_agent() {
    local node_name="$1"
    local agent_secret="$2"
    local jenkins_url="${3:-${JENKINS_URL}}"
    local work_dir="${4:-${AGENT_WORK_DIR}}"
    local agent_jar="${5:-${AGENT_JAR_PATH}}"
    
    validate_required_params "restart_jenkins_agent" node_name agent_secret
    
    log_step "Restarting Jenkins agent: ${node_name}"
    
    # Stop agent first
    stop_jenkins_agent "${node_name}"
    
    # Wait a moment
    sleep 2
    
    # Start agent
    start_jenkins_agent "${node_name}" "${agent_secret}" "${jenkins_url}" "${work_dir}" "${agent_jar}"
}

# Function: Get agent status
get_agent_status() {
    local node_name="$1"
    
    validate_required_params "get_agent_status" node_name
    
    log_info "Getting status for Jenkins agent: ${node_name}"
    
    local pid_file="/tmp/jenkins-agent-${node_name}.pid"
    local log_file="/tmp/jenkins-agent-${node_name}.log"
    
    if [[ -f "${pid_file}" ]]; then
        local agent_pid
        agent_pid=$(cat "${pid_file}")
        
        if kill -0 "${agent_pid}" 2>/dev/null; then
            log_success "Agent is running with PID: ${agent_pid}"
            
            # Show resource usage if ps is available
            if command -v ps >/dev/null 2>&1; then
                log_info "Process details:"
                ps -p "${agent_pid}" -o pid,ppid,cmd,etime,pcpu,pmem || true
            fi
        else
            log_warning "Agent PID file exists but process is not running"
        fi
    else
        log_info "No PID file found for agent: ${node_name}"
    fi
    
    # Check for running processes by name
    local running_procs
    if running_procs=$(pgrep -f "name ${node_name}" 2>/dev/null); then
        log_info "Found running agent processes: ${running_procs}"
    else
        log_info "No running agent processes found"
    fi
    
    # Show recent log entries if log file exists
    if [[ -f "${log_file}" ]]; then
        log_info "Recent log entries:"
        tail -10 "${log_file}" | while read -r line; do
            echo "  ${line}"
        done
    fi
}

# Function: Ensure agent is running (start if not online)
ensure_agent_running() {
    local node_name="$1"
    local agent_secret="$2"
    local jenkins_url="${3:-${JENKINS_URL}}"
    local work_dir="${4:-${AGENT_WORK_DIR}}"
    local agent_jar="${5:-${AGENT_JAR_PATH}}"
    
    validate_required_params "ensure_agent_running" node_name agent_secret
    
    log_step "Ensuring Jenkins agent is running: ${node_name}"
    
    if is_node_online "${node_name}"; then
        log_success "Agent '${node_name}' is already running"
        return 0
    else
        log_info "Agent '${node_name}' is not running, starting it"
        start_jenkins_agent "${node_name}" "${agent_secret}" "${jenkins_url}" "${work_dir}" "${agent_jar}"
    fi
}

# Function: Download Jenkins agent JAR if not present
download_agent_jar() {
    local jenkins_url="${1:-${JENKINS_URL}}"
    local agent_jar_path="${2:-${AGENT_JAR_PATH}}"
    
    validate_required_params "download_agent_jar" jenkins_url
    validate_command_exists "curl"
    
    if [[ -f "${agent_jar_path}" ]]; then
        log_info "Agent JAR already exists: ${agent_jar_path}"
        return 0
    fi
    
    log_step "Downloading Jenkins agent JAR"
    
    local agent_jar_url="${jenkins_url%/}/jnlpJars/agent.jar"
    
    log_info "Downloading from: ${agent_jar_url}"
    
    if curl -sSL -o "${agent_jar_path}" "${agent_jar_url}"; then
        log_success "Agent JAR downloaded: ${agent_jar_path}"
    else
        log_error "Failed to download agent JAR"
        return 1
    fi
}

# Function: Cleanup function for error handling
cleanup() {
    log_info "Performing node management cleanup"
    
    # Clean up any temporary files
    cleanup_temp_files "/tmp/jenkins-agent-*"
}

# Main function for command-line usage
main() {
    # Setup error handling
    setup_error_handling
    
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <action> [arguments...]"
        echo "Actions:"
        echo "  is-online <node_name>"
        echo "  start <node_name> <agent_secret> [jenkins_url] [work_dir] [agent_jar]"
        echo "  stop <node_name>"
        echo "  restart <node_name> <agent_secret> [jenkins_url] [work_dir] [agent_jar]"
        echo "  status <node_name>"
        echo "  ensure-running <node_name> <agent_secret> [jenkins_url] [work_dir] [agent_jar]"
        echo "  download-jar [jenkins_url] [agent_jar_path]"
        echo ""
        echo "Environment variables:"
        echo "  JENKINS_URL (default: http://192.168.0.122:8080/)"
        echo "  AGENT_JAR_PATH (default: agent.jar)"
        echo "  AGENT_NAME (default: slave)"
        echo "  AGENT_WORK_DIR (default: /var/jenkins_home)"
        echo ""
        echo "Examples:"
        echo "  $0 ensure-running slave 5b89654ec4e5e22a5a7ed38e022ef914493985f5edcc877624d14b63fd281fb2"
        echo "  $0 status slave"
        exit 1
    fi
    
    local action="$1"
    shift
    
    case "${action}" in
        is-online)
            [[ $# -eq 1 ]] || { echo "is-online requires: node_name"; exit 1; }
            is_node_online "$1"
            ;;
        start)
            [[ $# -ge 2 ]] || { echo "start requires: node_name agent_secret [jenkins_url] [work_dir] [agent_jar]"; exit 1; }
            start_jenkins_agent "$@"
            ;;
        stop)
            [[ $# -eq 1 ]] || { echo "stop requires: node_name"; exit 1; }
            stop_jenkins_agent "$1"
            ;;
        restart)
            [[ $# -ge 2 ]] || { echo "restart requires: node_name agent_secret [jenkins_url] [work_dir] [agent_jar]"; exit 1; }
            restart_jenkins_agent "$@"
            ;;
        status)
            [[ $# -eq 1 ]] || { echo "status requires: node_name"; exit 1; }
            get_agent_status "$1"
            ;;
        ensure-running)
            [[ $# -ge 2 ]] || { echo "ensure-running requires: node_name agent_secret [jenkins_url] [work_dir] [agent_jar]"; exit 1; }
            ensure_agent_running "$@"
            ;;
        download-jar)
            download_agent_jar "$@"
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