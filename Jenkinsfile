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
        TARGET_GROUP   = 'linux'
    }

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        ansiColor('xterm')
    }

    stages {
        stage('Pre-flight Checks') {
            steps {
                script {
                    echo "🔍 Performing pre-flight checks for Linux deployment..."
                    
                    // Validate required parameters
                    validateParameters(params, ['TARGET_HOST', 'PLAYBOOK', 'SSH_PASS'])
                    
                    // Check if inventory file exists
                    if (!fileExists(env.INVENTORY_FILE)) {
                        error "❌ Inventory file not found: ${env.INVENTORY_FILE}"
                    }
                    
                    // Check if playbook exists
                    def playbookPath = "${env.PLAYBOOKS_DIR}/${params.PLAYBOOK}"
                    if (!fileExists(playbookPath)) {
                        error "❌ Playbook not found: ${playbookPath}"
                    }
                    
                    echo "✅ Pre-flight checks completed successfully"
                }
            }
        }

        stage('Checkout Repository') {
            steps {
                echo "📥 Checking out repository for Linux deployment..."
                checkout scm
            }
        }

        stage('Parse Linux Inventory') {
            steps {
                script {
                    echo "🔍 Parsing inventory for Linux host: ${params.TARGET_HOST}"
                    
                    // Use shared library function for inventory parsing
                    def hostConfig = parseInventory(env.INVENTORY_FILE, params.TARGET_HOST, env.TARGET_GROUP)

                    env.TARGET_IP   = hostConfig.ansible_host
                    env.REMOTE_USER = hostConfig.ansible_user
                    env.PRIVATE_KEY = "${env.SSH_BASE_DIR}/${params.TARGET_HOST}/id_rsa"
                    env.PUBLIC_KEY  = "${env.PRIVATE_KEY}.pub"

                    echo "➡ Linux Host: ${params.TARGET_HOST}"
                    echo "➡ IP: ${env.TARGET_IP}"
                    echo "➡ Remote user: ${env.REMOTE_USER}"
                    echo "➡ SSH key path: ${env.PRIVATE_KEY}"
                }
            }
        }

        stage('Ensure SSH Key Exists') {
            steps {
                script {
                    echo "🔑 Managing SSH keys for ${params.TARGET_HOST}..."
                    
                    def keyExists = sh(script: "[ -f '${env.PRIVATE_KEY}' ] && echo yes || echo no", returnStdout: true).trim()

                    if (keyExists == "no") {
                        echo "🔑 SSH key not found in ${env.PRIVATE_KEY}. Generating..."
                        timeout(time: 2, unit: 'MINUTES') {
                            sh """
                                mkdir -p \$(dirname "${env.PRIVATE_KEY}")
                                ssh-keygen -t rsa -b 4096 -f "${env.PRIVATE_KEY}" -N '' -C "jenkins-${params.TARGET_HOST}-\$(date +%Y%m%d)"
                                chmod 600 "${env.PRIVATE_KEY}"
                                chmod 644 "${env.PUBLIC_KEY}"
                            """
                        }
                        
                        echo "📤 Sending public key to ${params.TARGET_HOST}..."
                        retry(2) {
                            timeout(time: 1, unit: 'MINUTES') {
                                sh """
                                    sshpass -p "${params.SSH_PASS}" ssh-copy-id -o StrictHostKeyChecking=no -o ConnectTimeout=30 -i "${env.PUBLIC_KEY}" ${env.REMOTE_USER}@${env.TARGET_IP} || true
                                """
                            }
                        }
                    } else {
                        echo "✅ SSH key already exists at ${env.PRIVATE_KEY}"
                        sh "chmod 600 ${env.PRIVATE_KEY}"
                    }
                }
            }
        }

        stage('Test SSH Connection') {
            steps {
                script {
                    echo "🔗 Testing SSH connection to ${params.TARGET_HOST}..."
                    
                    def sshTest = 1
                    retry(3) {
                        timeout(time: 1, unit: 'MINUTES') {
                            sshTest = sh(script: """
                                ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes -i ${env.PRIVATE_KEY} ${env.REMOTE_USER}@${env.TARGET_IP} 'echo "SSH connection successful"'
                            """, returnStatus: true)
                        }
                        
                        if (sshTest != 0) {
                            echo "⚠️ SSH connection failed, retrying..."
                            sleep(time: 5, unit: 'SECONDS')
                            error "SSH connection failed"
                        }
                    }

                    if (sshTest != 0) {
                        echo "❌ ERROR: Unable to establish SSH connection to ${params.TARGET_HOST} after retries."
                        cleanupSSHKeys(env.SSH_BASE_DIR, params.TARGET_HOST)
                        error "SSH connection failed permanently"
                    } else {
                        echo "✅ SSH connection established successfully"
                    }
                }
            }
        }

        stage('Run Ansible Playbook') {
            steps {
                script {
                    echo "🚀 Running Linux playbook: ${params.PLAYBOOK} on host ${params.TARGET_HOST}"
                    
                    timeout(time: 20, unit: 'MINUTES') {
                        dir(env.PLAYBOOKS_DIR) {
                            sh """
                                set -e
                                echo "📋 Validating playbook syntax..."
                                ansible-playbook --syntax-check -i ../inventories/hosts.yml ${params.PLAYBOOK}
                                
                                echo "🎯 Executing playbook with verbose output..."
                                sshpass -p "${params.SSH_PASS}" ansible-playbook \
                                    -i ../inventories/hosts.yml \
                                    ${params.PLAYBOOK} \
                                    -K \
                                    --limit ${params.TARGET_HOST} \
                                    -e "hosts_to_deploy=${params.TARGET_HOST}" \
                                    -v \
                                    --diff
                            """
                        }
                    }
                    
                    echo "✅ Ansible playbook execution completed successfully"
                }
            }
        }
    }

    post {
        always {
            script {
                def duration = currentBuild.duration ? currentBuild.duration / 1000 : 'unknown'
                echo "📊 Deployment finished in ${duration} seconds"
            }
        }
        success {
            echo "✅ Linux deployment completed successfully for ${params.TARGET_HOST}"
        }
        failure {
            script {
                echo "❌ Linux deployment failed for ${params.TARGET_HOST}"
                // Clean up on failure to ensure fresh start next time
                try {
                    cleanupSSHKeys(env.SSH_BASE_DIR, params.TARGET_HOST)
                } catch (Exception e) {
                    echo "⚠️ Failed to cleanup SSH keys: ${e.message}"
                }
            }
        }
        unstable {
            echo "⚠️ Linux deployment completed with warnings for ${params.TARGET_HOST}"
        }
    }
}
