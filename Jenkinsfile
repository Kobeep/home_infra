pipeline {
    agent { label 'slave' }

    parameters {
        string(name: 'TARGET_HOST', defaultValue: '', description: 'Target Linux host from inventory')
        string(name: 'PLAYBOOK', defaultValue: '', description: 'Playbook to run on Linux')
        password(name: 'SSH_PASS', defaultValue: '', description: 'SSH password for the target host')
    }

    environment {
        INVENTORY_FILE = 'ansible/inventories/hosts.yml'
        PLAYBOOKS_DIR  = 'ansible/playbooks'
        SSH_BASE_DIR   = '/var/jenkins_home/.ssh'
    }

    stages {
        stage('Checkout Repository') {
            steps {
                echo "📥 Checking out repository for Linux deployment..."
                checkout scm
            }
        }

        stage('Validate Parameters') {
            steps {
                script {
                    if (!params.TARGET_HOST) {
                        error "TARGET_HOST parameter is required"
                    }
                    if (!params.PLAYBOOK) {
                        error "PLAYBOOK parameter is required"
                    }
                    if (!params.SSH_PASS) {
                        error "SSH_PASS parameter is required"
                    }
                }
            }
        }

        stage('Deploy to Linux Host') {
            steps {
                echo "🚀 Deploying Linux playbook: ${params.PLAYBOOK} to host: ${params.TARGET_HOST}"
                sh '''
                    chmod +x scripts/linux/deploy-linux.sh
                    scripts/linux/deploy-linux.sh deploy "${TARGET_HOST}" "${PLAYBOOK}" "${SSH_PASS}"
                '''
            }
        }
    }

    post {
        always {
            echo "Linux deployment finished."
        }
        success {
            echo "✅ Linux deployment completed successfully."
        }
        failure {
            echo "❌ Linux deployment failed. Check logs for details."
        }
    }
}
