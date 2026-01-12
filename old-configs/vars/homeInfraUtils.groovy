/**
 * Shared Jenkins Library for Home Infrastructure Pipelines
 * Provides common utilities for deployment, backup, and configuration management
 * 
 * @author Jenkins CI
 * @version 1.0.0
 */

/**
 * Parse Ansible inventory file and extract host configuration
 * @param inventoryFile Path to the YAML inventory file
 * @param hostGroup Group name (e.g., 'linux', 'windows')
 * @param targetHost Host name to look up
 * @return Map containing host configuration (ansible_host, ansible_user, etc.)
 */
def parseInventory(String inventoryFile, String hostGroup, String targetHost) {
    validateParameters([
        inventoryFile: inventoryFile,
        hostGroup: hostGroup,
        targetHost: targetHost
    ])
    
    try {
        echo "🔍 Parsing inventory for host: ${targetHost} in group: ${hostGroup}"
        
        def inv = readYaml file: inventoryFile
        def hostConfig = null
        
        if (inv?.all?.children?.containsKey(hostGroup)) {
            def group = inv.all.children[hostGroup]
            if (group?.hosts?.containsKey(targetHost)) {
                hostConfig = group.hosts[targetHost]
            }
        }
        
        if (!hostConfig) {
            error "❌ Host '${targetHost}' not found in group '${hostGroup}' in inventory file: ${inventoryFile}"
        }
        
        // Validate required fields
        if (!hostConfig.ansible_host) {
            error "❌ Missing 'ansible_host' for host '${targetHost}'"
        }
        if (!hostConfig.ansible_user) {
            error "❌ Missing 'ansible_user' for host '${targetHost}'"
        }
        
        echo "✅ Successfully parsed inventory for ${targetHost}"
        echo "   IP: ${hostConfig.ansible_host}"
        echo "   User: ${hostConfig.ansible_user}"
        
        return hostConfig
    } catch (Exception e) {
        error "❌ Failed to parse inventory: ${e.getMessage()}"
    }
}

/**
 * Get list of available hosts from inventory for a specific group
 * @param inventoryFile Path to the YAML inventory file
 * @param hostGroup Group name (e.g., 'linux', 'windows')
 * @return List of available host names
 */
def getAvailableHosts(String inventoryFile, String hostGroup) {
    validateParameters([
        inventoryFile: inventoryFile,
        hostGroup: hostGroup
    ])
    
    try {
        def inv = readYaml file: inventoryFile
        def hosts = []
        
        if (inv?.all?.children?.containsKey(hostGroup)) {
            def group = inv.all.children[hostGroup]
            if (group?.hosts) {
                hosts = group.hosts.keySet().toList()
            }
        }
        
        if (hosts.isEmpty()) {
            error "❌ No hosts found for group '${hostGroup}' in inventory file: ${inventoryFile}"
        }
        
        echo "✅ Found ${hosts.size()} hosts in group '${hostGroup}': ${hosts.join(', ')}"
        return hosts
    } catch (Exception e) {
        error "❌ Failed to get available hosts: ${e.getMessage()}"
    }
}

/**
 * Get list of available playbooks from the playbooks directory
 * @param playbooksDir Path to the playbooks directory
 * @return List of available playbook files
 */
def getAvailablePlaybooks(String playbooksDir) {
    validateParameter('playbooksDir', playbooksDir)
    
    try {
        def playbooksOutput = sh(
            script: "find ${playbooksDir} -name '*.yml' -type f | xargs -r -n1 basename | sort",
            returnStdout: true
        ).trim()
        
        if (!playbooksOutput) {
            error "❌ No playbooks found in directory: ${playbooksDir}"
        }
        
        def playbooks = playbooksOutput.tokenize("\n")
        echo "✅ Found ${playbooks.size()} playbooks: ${playbooks.join(', ')}"
        return playbooks
    } catch (Exception e) {
        error "❌ Failed to get available playbooks: ${e.getMessage()}"
    }
}

/**
 * Setup SSH key for secure connection to remote host
 * @param sshBaseDir Base directory for SSH keys
 * @param targetHost Target hostname
 * @param targetIp Target IP address
 * @param remoteUser Remote username
 * @param password SSH password (will be used only for initial key setup)
 * @return Map containing private and public key paths
 */
def setupSSHKey(String sshBaseDir, String targetHost, String targetIp, String remoteUser, String password) {
    validateParameters([
        sshBaseDir: sshBaseDir,
        targetHost: targetHost,
        targetIp: targetIp,
        remoteUser: remoteUser,
        password: password
    ])
    
    def privateKey = "${sshBaseDir}/${targetHost}/id_rsa"
    def publicKey = "${privateKey}.pub"
    
    try {
        def keyExists = sh(
            script: "[ -f '${privateKey}' ] && echo 'yes' || echo 'no'",
            returnStdout: true
        ).trim()
        
        if (keyExists == "no") {
            echo "🔑 SSH key not found for ${targetHost}. Generating new key pair..."
            sh """
                mkdir -p \$(dirname "${privateKey}")
                ssh-keygen -t rsa -b 4096 -f "${privateKey}" -N '' -C "jenkins-${targetHost}-\$(date +%Y%m%d)"
                chmod 600 "${privateKey}"
                chmod 644 "${publicKey}"
            """
            
            echo "📤 Installing public key on ${targetHost}..."
            def sshCopyResult = sh(
                script: """
                    sshpass -p '${password}' ssh-copy-id -o StrictHostKeyChecking=no -i "${publicKey}" ${remoteUser}@${targetIp}
                """,
                returnStatus: true
            )
            
            if (sshCopyResult != 0) {
                echo "⚠️  ssh-copy-id failed, but continuing (key might already be installed)"
            }
        } else {
            echo "✅ SSH key already exists for ${targetHost}"
            sh "chmod 600 '${privateKey}'"
        }
        
        return [
            privateKey: privateKey,
            publicKey: publicKey
        ]
    } catch (Exception e) {
        error "❌ Failed to setup SSH key: ${e.getMessage()}"
    }
}

/**
 * Test SSH connection to remote host
 * @param privateKey Path to private SSH key
 * @param remoteUser Remote username
 * @param targetIp Target IP address
 * @param targetHost Target hostname (for logging)
 * @param timeout Connection timeout in seconds (default: 30)
 * @return boolean true if connection successful
 */
def testSSHConnection(String privateKey, String remoteUser, String targetIp, String targetHost, int timeout = 30) {
    validateParameters([
        privateKey: privateKey,
        remoteUser: remoteUser,
        targetIp: targetIp,
        targetHost: targetHost
    ])
    
    try {
        echo "🔌 Testing SSH connection to ${targetHost} (${targetIp})..."
        
        def result = sh(
            script: """
                timeout ${timeout} ssh -o StrictHostKeyChecking=no -o ConnectTimeout=${timeout} -o BatchMode=yes \
                    -i '${privateKey}' ${remoteUser}@${targetIp} 'echo "SSH_CONNECTION_OK"'
            """,
            returnStatus: true
        )
        
        if (result == 0) {
            echo "✅ SSH connection to ${targetHost} successful"
            return true
        } else {
            echo "❌ SSH connection to ${targetHost} failed"
            return false
        }
    } catch (Exception e) {
        echo "❌ SSH connection test failed: ${e.getMessage()}"
        return false
    }
}

/**
 * Run Ansible playbook with proper error handling and logging
 */
def runAnsiblePlaybook(Map config) {
    // Validate required parameters
    def requiredParams = ['playbooksDir', 'inventoryFile', 'playbook', 'targetHost', 'password', 'platform']
    requiredParams.each { param ->
        if (!config.containsKey(param) || !config[param]) {
            error "❌ Missing required parameter: ${param}"
        }
    }
    
    try {
        echo "🚀 Running Ansible playbook: ${config.playbook}"
        echo "   Target: ${config.targetHost}"
        echo "   Platform: ${config.platform}"
        
        def extraVarsStr = ""
        if (config.extraVars) {
            def vars = config.extraVars.collect { k, v -> "${k}=${v}" }.join(" ")
            extraVarsStr = "-e \"${vars}\""
        }
        
        def ansibleCmd = ""
        if (config.platform == 'windows') {
            ansibleCmd = """
                cd ${config.playbooksDir}
                ansible-playbook -i ../inventories/hosts.yml ${config.playbook} \
                    --limit ${config.targetHost} \
                    -e "ansible_password=${config.password}" \
                    ${extraVarsStr} \
                    -v
            """
        } else {
            ansibleCmd = """
                cd ${config.playbooksDir}
                sshpass -p '${config.password}' ansible-playbook -i ../inventories/hosts.yml ${config.playbook} \
                    --limit ${config.targetHost} \
                    -K ${extraVarsStr} \
                    -v
            """
        }
        
        def result = sh(
            script: ansibleCmd,
            returnStatus: true
        )
        
        if (result == 0) {
            echo "✅ Ansible playbook completed successfully"
        } else {
            error "❌ Ansible playbook failed with exit code: ${result}"
        }
        
    } catch (Exception e) {
        error "❌ Failed to run Ansible playbook: ${e.getMessage()}"
    }
}

/**
 * Validate that required parameters are not null or empty
 */
def validateParameters(Map params) {
    params.each { name, value ->
        validateParameter(name, value)
    }
}

/**
 * Validate that a single parameter is not null or empty
 */
def validateParameter(String name, Object value) {
    if (value == null || (value instanceof String && value.trim().isEmpty())) {
        error "❌ Parameter '${name}' is required and cannot be null or empty"
    }
}

/**
 * Standard cleanup operations for pipeline post-execution
 */
def cleanup(String sshBaseDir = null, String targetHost = null, boolean cleanupTempFiles = true) {
    try {
        echo "🧹 Performing cleanup operations..."
        
        if (cleanupTempFiles) {
            sh "find /tmp -name 'jenkins-*' -type f -mtime +1 -delete 2>/dev/null || true"
        }
        
        // Only clean SSH keys if explicitly requested and connection failed
        if (sshBaseDir && targetHost && currentBuild.result == 'FAILURE') {
            echo "⚠️  Cleaning up SSH keys for failed connection to ${targetHost}"
            sh "rm -rf ${sshBaseDir}/${targetHost} || true"
        }
        
        echo "✅ Cleanup completed"
    } catch (Exception e) {
        echo "⚠️  Cleanup failed (non-critical): ${e.getMessage()}"
    }
}