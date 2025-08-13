#!/usr/bin/env groovy

/**
 * Clean up SSH key directory if connection fails
 * @param sshBaseDir Base SSH directory
 * @param targetHost Target hostname
 */
def call(String sshBaseDir, String targetHost) {
    try {
        sh "rm -rfv ${sshBaseDir}/${targetHost}"
        echo "🧹 Cleaned up SSH directory for ${targetHost}"
    } catch (Exception e) {
        echo "⚠️ Failed to clean up SSH directory: ${e.message}"
    }
}