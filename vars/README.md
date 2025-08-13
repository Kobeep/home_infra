# Jenkins Shared Library for Home Infrastructure

This shared library provides common utilities and functions for Jenkins pipelines in the home infrastructure project. It eliminates code duplication, improves security, and implements industry best practices.

## Features

- **Secure Credential Management**: No hardcoded secrets or passwords
- **Parameter Validation**: Comprehensive input validation and sanitization
- **Error Handling**: Robust error handling with detailed logging
- **SSH Key Management**: Automated SSH key generation and management
- **Ansible Integration**: Streamlined Ansible playbook execution
- **Inventory Parsing**: Centralized YAML inventory parsing
- **Timeout Handling**: Configurable timeouts for all operations
- **Comprehensive Logging**: Professional logging with emojis and status indicators

## Usage

To use this shared library in your Jenkinsfile, add the following annotation at the top:

```groovy
@Library('homeInfraUtils') _
```

## Available Functions

### Inventory Management

#### `parseInventory(inventoryFile, hostGroup, targetHost)`
Parses Ansible inventory YAML file and extracts host configuration.

**Parameters:**
- `inventoryFile`: Path to the YAML inventory file
- `hostGroup`: Group name (e.g., 'linux', 'windows')
- `targetHost`: Host name to look up

**Returns:** Map containing host configuration (ansible_host, ansible_user, etc.)

**Example:**
```groovy
def hostConfig = homeInfraUtils.parseInventory(
    'ansible/inventories/hosts.yml',
    'linux',
    'server1'
)
```

#### `getAvailableHosts(inventoryFile, hostGroup)`
Gets list of available hosts from inventory for a specific group.

**Parameters:**
- `inventoryFile`: Path to the YAML inventory file
- `hostGroup`: Group name (e.g., 'linux', 'windows')

**Returns:** List of available host names

#### `getAvailablePlaybooks(playbooksDir)`
Gets list of available playbooks from the playbooks directory.

**Parameters:**
- `playbooksDir`: Path to the playbooks directory

**Returns:** List of available playbook files

### SSH Management

#### `setupSSHKey(sshBaseDir, targetHost, targetIp, remoteUser, password)`
Sets up SSH key for secure connection to remote host.

**Parameters:**
- `sshBaseDir`: Base directory for SSH keys
- `targetHost`: Target hostname
- `targetIp`: Target IP address
- `remoteUser`: Remote username
- `password`: SSH password (used only for initial key setup)

**Returns:** Map containing private and public key paths

#### `testSSHConnection(privateKey, remoteUser, targetIp, targetHost, timeout)`
Tests SSH connection to remote host.

**Parameters:**
- `privateKey`: Path to private SSH key
- `remoteUser`: Remote username
- `targetIp`: Target IP address
- `targetHost`: Target hostname (for logging)
- `timeout`: Connection timeout in seconds (default: 30)

**Returns:** Boolean indicating connection success

### Ansible Integration

#### `runAnsiblePlaybook(config)`
Runs Ansible playbook with proper error handling and logging.

**Parameters:**
- `config`: Map containing:
  - `playbooksDir`: Path to playbooks directory
  - `inventoryFile`: Path to inventory file
  - `playbook`: Playbook filename
  - `targetHost`: Target host to limit execution to
  - `password`: Authentication password (SSH or WinRM)
  - `platform`: Platform type ('linux' or 'windows')
  - `extraVars`: Map of extra variables to pass to ansible (optional)

**Example:**
```groovy
homeInfraUtils.runAnsiblePlaybook([
    playbooksDir: 'ansible/playbooks',
    inventoryFile: '../inventories/hosts.yml',
    playbook: 'site.yml',
    targetHost: 'server1',
    password: params.SSH_PASS,
    platform: 'linux',
    extraVars: [
        hosts_to_deploy: 'server1'
    ]
])
```

### Validation Utilities

#### `validateParameters(params)`
Validates that required parameters are not null or empty.

**Parameters:**
- `params`: Map of parameter names to values

#### `validateParameter(name, value)`
Validates that a single parameter is not null or empty.

**Parameters:**
- `name`: Parameter name (for error messages)
- `value`: Parameter value to validate

### Utility Functions

#### `cleanup(sshBaseDir, targetHost, cleanupTempFiles)`
Standard cleanup operations for pipeline post-execution.

**Parameters:**
- `sshBaseDir`: SSH base directory (optional)
- `targetHost`: Target host (optional, for cleaning up specific SSH keys on failure)
- `cleanupTempFiles`: Whether to clean up temporary files (default: true)

## Security Best Practices

This shared library implements several security best practices:

1. **No Hardcoded Credentials**: All sensitive data is passed via Jenkins credentials
2. **Parameter Validation**: All inputs are validated before use
3. **Secure SSH Key Management**: SSH keys are generated with proper permissions
4. **Timeout Protection**: All operations have configurable timeouts
5. **Error Handling**: Comprehensive error handling prevents information leakage
6. **Cleanup Operations**: Automatic cleanup of sensitive data and temporary files

## Error Handling

All functions include comprehensive error handling:

- **Input Validation**: Parameters are validated before processing
- **Timeout Protection**: Operations have configurable timeouts
- **Exception Handling**: Try-catch blocks with detailed error messages
- **Graceful Degradation**: Non-critical operations fail gracefully
- **Cleanup on Failure**: Automatic cleanup of resources on failure

## Logging Standards

The library uses standardized logging with:

- **Emoji Indicators**: Visual status indicators (🚀 ✅ ❌ ⚠️)
- **Structured Messages**: Consistent message formatting
- **Progress Tracking**: Clear progress indicators
- **Error Details**: Detailed error information for troubleshooting

## Version History

### v2.0.0 (Current)
- Complete rewrite with professional standards
- Added comprehensive parameter validation
- Implemented secure credential management
- Added timeout handling for all operations
- Comprehensive error handling and logging
- Eliminated code duplication across pipelines

### v1.0.0 (Legacy)
- Basic pipeline functionality
- Hardcoded credentials (security risk)
- Limited error handling
- Code duplication across pipelines

## Migration Guide

To migrate from legacy pipelines to the new shared library:

1. Add `@Library('homeInfraUtils') _` to your Jenkinsfile
2. Replace inline Python scripts with `parseInventory()` calls
3. Replace SSH key management code with `setupSSHKey()` and `testSSHConnection()`
4. Replace Ansible execution with `runAnsiblePlaybook()`
5. Add parameter validation with `validateParameters()`
6. Add cleanup in post section with `cleanup()`

## Contributing

When contributing to this shared library:

1. Follow the existing code style and naming conventions
2. Add comprehensive documentation for new functions
3. Include parameter validation for all inputs
4. Add proper error handling and logging
5. Update this README with new functions
6. Test changes thoroughly before committing

## Support

For issues or questions regarding this shared library:

1. Check the Jenkins build logs for detailed error messages
2. Verify parameter values and types
3. Ensure Jenkins credentials are properly configured
4. Review the function documentation above
5. Check for any recent changes in the pipeline code