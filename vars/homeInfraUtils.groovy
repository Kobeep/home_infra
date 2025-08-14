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
 * Another test method
 */
def simpleTest() {
    echo "✅ simpleTest method works!"
    return "OK"
}

/**
 * Simple SSH key setup for testing
 */
def setupSSHKey(sshBaseDir, targetHost, targetIp, remoteUser, password) {
    echo "🔐 setupSSHKey called for ${targetHost}"
    echo "   SSH Base Dir: ${sshBaseDir}"
    echo "   Target IP: ${targetIp}"
    echo "   Remote User: ${remoteUser}"
    
    def privateKey = "${sshBaseDir}/${targetHost}/id_rsa"
    def publicKey = "${privateKey}.pub"
    
    return [
        privateKey: privateKey,
        publicKey: publicKey
    ]
}