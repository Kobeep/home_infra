pipeline {
    agent any

    parameters {
        string(name: 'TARGET_HOST', defaultValue: '', description: 'Target Host')
        string(name: 'PLAYBOOK', defaultValue: '', description: 'Playbook to run')
        password(name: 'SSH_PASS', defaultValue: '', description: 'SSH Password for the target host')
    }

    environment {
        INVENTORY_FILE = 'ansible/inventories/hosts.yml'
        PLAYBOOKS_DIR  = 'ansible/playbooks'
    }

    stages {
        stage('Checkout Repository') {
            steps {
                echo "📥 Checking out repository for deployment..."
                checkout scm
            }
        }

        stage('Parse Inventory') {
            steps {
                script {
                    // Fetch the host configuration for the TARGET_HOST from the inventory
                    def inventoryJson = sh(script: """
                        python3 -c '
import sys, yaml, json
with open("${INVENTORY_FILE}") as f:
    inv = yaml.safe_load(f)
    print(json.dumps(inv["all"]["hosts"]["${params.TARGET_HOST}"]))
                        '
                    """, returnStdout: true).trim()

                    def hostConfig = readJSON text: inventoryJson

                    // Set values
                    env.TARGET_IP   = hostConfig.ansible_host
                    env.REMOTE_USER = hostConfig.ansible_user
                    env.PRIVATE_KEY = hostConfig.ansible_ssh_private_key_file
                    env.PUBLIC_KEY  = "${env.PRIVATE_KEY}.pub"

                    echo "Target host: ${params.TARGET_HOST} (IP: ${env.TARGET_IP})"
                }
            }
        }

        stage('Ensure SSH Key Exists') {
            steps {
                script {
                    def keyExists = sh(script: "[ -f '${env.PRIVATE_KEY}' ] && echo yes || echo no", returnStdout: true).trim()

                    if (keyExists == "no") {
                        echo "🔑 SSH key not found. Generating..."
                        sh """
                            mkdir -p \$(dirname "${env.PRIVATE_KEY}")
                            ssh-keygen -t rsa -b 4096 -f "${env.PRIVATE_KEY}" -N ''
                        """
                    } else {
                        echo "✅ SSH key already exists."
                    }
                }
            }
        }

        stage('Send Public Key') {
            steps {
                script {
                    echo "📤 Sending public key to ${params.TARGET_HOST}..."
                    sh """
                        sshpass -p "${params.SSH_PASS}" ssh-copy-id -i "${env.PUBLIC_KEY}" ${env.REMOTE_USER}@${env.TARGET_IP} || true
                    """
                }
            }
        }

        stage('Test SSH Connection') {
            steps {
                script {
                    def result = sh(script: """
                        ssh -o StrictHostKeyChecking=no -i ${env.PRIVATE_KEY} ${env.REMOTE_USER}@${env.TARGET_IP} 'echo OK'
                    """, returnStatus: true)

                    if (result != 0) {
                        error "❌ ERROR: Cannot connect to ${params.TARGET_HOST} via SSH."
                    } else {
                        echo "✅ SSH connection successful."
                    }
                }
            }
        }

        stage('Run Ansible Playbook') {
            steps {
                echo "🚀 Running playbook: ${params.PLAYBOOK} on host ${params.TARGET_HOST}"
                sh """
                    ansible-playbook -i ${INVENTORY_FILE} ${PLAYBOOKS_DIR}/${params.PLAYBOOK} --limit ${params.TARGET_HOST}
                """
            }
        }
    }
}
