# Pipeline Scripts Documentation

This directory contains refactored scripts that were extracted from Jenkinsfiles to improve maintainability, readability, and reusability.

## Directory Structure

```
scripts/
├── common/               # Shared utilities and functions
│   ├── inventory-parser.py    # Ansible inventory parsing
│   ├── ssh-manager.sh         # SSH key management
│   ├── git-operations.sh      # Git commit/push operations
│   └── utils.sh               # Common utility functions
├── linux/                # Linux deployment scripts
│   └── deploy-linux.sh        # Complete Linux deployment workflow
├── windows/              # Windows deployment scripts
│   └── deploy-windows.sh      # Complete Windows deployment workflow
├── backup/               # Backup operations
│   └── jenkins-backup.sh      # Jenkins pipeline backup
├── node/                 # Node management
│   └── start-slave.sh         # Jenkins node/agent management
└── docs/                 # Documentation
    └── README.md              # This file
```

## Common Scripts

### inventory-parser.py
Python script for parsing Ansible inventory YAML files.

**Usage:**
```bash
python3 inventory-parser.py <inventory_file> <target_host> [--group <group>]
python3 inventory-parser.py <inventory_file> --list-hosts [--group <group>]
```

**Features:**
- Parse host configuration from YAML inventory
- Support for group filtering (linux/windows)
- List all hosts in inventory or specific group
- JSON output for easy integration
- Comprehensive error handling

### ssh-manager.sh
Comprehensive SSH key management for remote host connections.

**Usage:**
```bash
./ssh-manager.sh <action> <host_name> [arguments...]

Actions:
  generate <host_name>                              # Generate SSH key pair
  exists <host_name>                               # Check if key exists
  deploy <host_name> <target_ip> <remote_user> <ssh_password>
  test <host_name> <target_ip> <remote_user>
  ensure <host_name> <target_ip> <remote_user> <ssh_password>
  cleanup <host_name>                              # Remove keys
```

**Features:**
- Automatic SSH key generation
- Public key deployment to remote hosts
- Connection testing
- Key cleanup and regeneration
- Proper file permissions management

### git-operations.sh
Git operations including authenticated commits and pushes.

**Usage:**
```bash
./git-operations.sh <action> [arguments...]

Actions:
  setup-config [email] [name]
  setup-auth <user> <pass> [remote]
  add <file1> [file2] ...
  commit <message> [allow-empty]
  push [remote] [branch]
  workflow <message> <user> <pass> [files...]
  status
  timestamp [format]
```

**Features:**
- Secure credential handling
- Complete git workflow automation
- Repository status checking
- Automatic cleanup of credentials
- Timestamping utilities

### utils.sh
Common utility functions used across all scripts.

**Features:**
- Colored logging functions (info, success, warning, error)
- Parameter validation
- File and directory operations
- Process management
- Network utilities
- Error handling setup

## Deployment Scripts

### Linux Deployment (deploy-linux.sh)
Complete Linux deployment workflow using Ansible.

**Usage:**
```bash
./deploy-linux.sh deploy <target_host> <playbook> <ssh_password> [extra_vars]
./deploy-linux.sh list-hosts
./deploy-linux.sh list-playbooks
./deploy-linux.sh parse-inventory <target_host>
```

**Workflow:**
1. Parse inventory for target host
2. Validate playbook exists
3. Ensure SSH connectivity (generate keys if needed)
4. Execute Ansible playbook with proper parameters
5. Comprehensive error handling and logging

### Windows Deployment (deploy-windows.sh)
Complete Windows deployment workflow using Ansible and WinRM.

**Usage:**
```bash
./deploy-windows.sh deploy <target_host> <playbook> <winrm_password> [extra_vars]
./deploy-windows.sh list-hosts
./deploy-windows.sh list-playbooks
./deploy-windows.sh test-winrm <target_host> <winrm_password>
```

**Workflow:**
1. Parse inventory for target Windows host
2. Validate playbook (with Windows-specific checks)
3. Test WinRM connectivity
4. Execute Ansible playbook with WinRM authentication
5. Specialized Windows error handling

## Supporting Scripts

### Jenkins Backup (jenkins-backup.sh)
Comprehensive Jenkins pipeline and configuration backup.

**Usage:**
```bash
./jenkins-backup.sh backup-pipelines <backup_dir>
./jenkins-backup.sh backup-system-config <backup_dir>
./jenkins-backup.sh complete-backup [backup_dir] [include_system_config] [clean_old] [retention_days]
```

**Features:**
- Pipeline job backup (excludes build logs)
- System configuration backup
- Old backup cleanup with retention
- Backup validation
- Comprehensive logging

### Node Management (start-slave.sh)
Jenkins node/agent lifecycle management.

**Usage:**
```bash
./start-slave.sh ensure-running <node_name> <agent_secret>
./start-slave.sh status <node_name>
./start-slave.sh start <node_name> <agent_secret>
./start-slave.sh stop <node_name>
```

**Features:**
- Agent availability checking
- Background agent startup
- Process monitoring and management
- Agent JAR download
- Comprehensive status reporting

## Environment Variables

All scripts support environment variable configuration:

### Common Variables
- `INVENTORY_FILE`: Ansible inventory file path (default: ansible/inventories/hosts.yml)
- `PLAYBOOKS_DIR`: Ansible playbooks directory (default: ansible/playbooks)
- `SSH_BASE_DIR`: SSH keys base directory (default: /var/jenkins_home/.ssh)

### Jenkins-Specific Variables
- `JENKINS_HOME`: Jenkins home directory (default: /var/jenkins_home)
- `JENKINS_URL`: Jenkins server URL (default: http://192.168.0.122:8080/)
- `AGENT_NAME`: Default agent name (default: slave)

## Error Handling

All scripts implement comprehensive error handling:

- **Immediate exit on errors** (`set -euo pipefail`)
- **Parameter validation** with clear error messages
- **Cleanup functions** for temporary files and resources
- **Trap-based error handling** for unexpected failures
- **Colored logging** for easy identification of issues

## Integration with Jenkinsfiles

The scripts are designed to be called from Jenkinsfiles like this:

```groovy
// Linux deployment
sh '''
    chmod +x scripts/linux/deploy-linux.sh
    scripts/linux/deploy-linux.sh deploy "${TARGET_HOST}" "${PLAYBOOK}" "${SSH_PASS}"
'''

// Windows deployment
sh '''
    chmod +x scripts/windows/deploy-windows.sh
    scripts/windows/deploy-windows.sh deploy "${TARGET_HOST}" "${PLAYBOOK}" "${WINRM_PASS}"
'''
```

## Benefits of Refactoring

1. **Maintainability**: Logic is separated into focused, single-purpose scripts
2. **Reusability**: Scripts can be used across multiple pipelines
3. **Testability**: Scripts can be tested independently
4. **Readability**: Jenkinsfiles are now much cleaner and easier to understand
5. **Debugging**: Issues can be debugged more easily in isolated scripts
6. **Documentation**: Each script is self-documenting with help text
7. **Error Handling**: Comprehensive error handling throughout
8. **Standards**: Consistent coding standards and patterns

## Migration Notes

When migrating from the old Jenkinsfiles:

1. The core functionality remains exactly the same
2. Environment variables are preserved
3. Error conditions are handled more robustly
4. Additional validation and logging is provided
5. Scripts can be run independently for testing

## Testing Scripts

Each script can be tested independently:

```bash
# Test inventory parsing
./scripts/common/inventory-parser.py ansible/inventories/hosts.yml --list-hosts --group linux

# Test SSH connectivity
./scripts/linux/deploy-linux.sh parse-inventory <hostname>

# Test backup functionality
./scripts/backup/jenkins-backup.sh backup-pipelines test-backup
```