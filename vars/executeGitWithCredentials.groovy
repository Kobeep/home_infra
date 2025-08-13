#!/usr/bin/env groovy

/**
 * Execute Git operations with credentials safely
 * @param credentialsId Jenkins credentials ID
 * @param closure Closure containing git operations
 */
def call(String credentialsId, Closure closure) {
    withCredentials([usernamePassword(
        credentialsId: credentialsId,
        usernameVariable: 'GIT_USER',
        passwordVariable: 'GIT_PASS'
    )]) {
        try {
            // Configure git user
            sh '''
                git config user.email "jenkins@localhost"
                git config user.name  "Jenkins CI"
            '''
            
            // Setup authenticated URL
            sh '''
                ORIG_URL=$(git remote get-url origin)
                AUTH_URL=$(echo "$ORIG_URL" | sed -e "s#https://#https://${GIT_USER}:${GIT_PASS}@#")
                git remote set-url origin "$AUTH_URL"
            '''
            
            // Execute the closure with git operations
            closure()
            
        } finally {
            // Clean up by resetting to original URL (without credentials)
            try {
                sh '''
                    ORIG_URL=$(git remote get-url origin | sed -e "s#https://.*@#https://#")
                    git remote set-url origin "$ORIG_URL"
                '''
            } catch (Exception e) {
                echo "⚠️ Failed to reset git URL: ${e.message}"
            }
        }
    }
}