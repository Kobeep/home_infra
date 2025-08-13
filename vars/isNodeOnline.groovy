#!/usr/bin/env groovy

/**
 * Check if a Jenkins agent node is online
 * @param nodeName Name of the Jenkins agent node
 * @return Boolean indicating if the node is online
 */
def call(String nodeName) {
    try {
        def node = Jenkins.instance.getNode(nodeName)
        def computer = node?.toComputer()
        return computer?.isOnline() ?: false
    } catch (Exception e) {
        echo "⚠️ Error checking node status: ${e.message}"
        return false
    }
}