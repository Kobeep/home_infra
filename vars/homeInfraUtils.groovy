/**
 * Minimal Jenkins Shared Library for Testing
 * 
 * @author Jenkins CI
 * @version 1.0.0-test
 */

/**
 * Simple test method to verify library loading
 */
def test() {
    echo "✅ homeInfraUtils library is working!"
    return "success"
}

/**
 * Setup SSH key for secure connection to remote host
 */
def setupSSHKey(sshBaseDir, targetHost, targetIp, remoteUser, password) {
    echo "🔐 setupSSHKey called for ${targetHost}"
    echo "   SSH Base Dir: ${sshBaseDir}"
    echo "   Target IP: ${targetIp}"
    echo "   Remote User: ${remoteUser}"
    
    def privateKey = "${sshBaseDir}/${targetHost}/id_rsa"
    def publicKey = "${privateKey}.pub"
    
    try {
        // Check if key exists
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
 */
def testSSHConnection(privateKey, remoteUser, targetIp, targetHost, timeout = 30) {
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