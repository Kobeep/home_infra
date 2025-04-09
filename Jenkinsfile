pipeline {
    agent any

    parameters {
        choice(name: 'TARGET_HOST', choices: ['szymonpc', 'kubapc', 'hpserver', 'mainserver'], description: 'Select the target host')
        choice(name: 'PLAYBOOK', choices: ['hp.yml', 'server.yml'], description: 'Choose the playbook to run')
    }

    environment {
        INVENTORY_FILE = 'inventories/hosts.yml'
    }

    stages {
        stage('Checkout Repo') {
            steps {
                echo "📥 Checking out source code..."
                checkout scm
            }
        }

        stage('Parse Inventory') {
            steps {
                script {
                    def inventoryJson = sh(script: """
                        python3 -c '
import sys, yaml, json
with open("${INVENTORY_FILE}") as f:
    inv = yaml.safe_load(f)
    print(json.dumps(inv["all"]["hosts"]["${params.TARGET_HOST}"]))
                        '
                    """, returnStdout: true).trim()

                    def hostConfig = readJSON text: inventoryJson

                    env.TARGET_IP = hostConfig.ansible_host
                    env.REMOTE_USER = hostConfig.ansible_user
                    env.PRIVATE_KEY = hostConfig.ansible_ssh_private_key_file
                    env.PUBLIC_KEY = "${env.PRIVATE_KEY}.pub"

                    echo "➡ Target: ${params.TARGET_HOST}"
                    echo "➡ IP: ${env.TARGET_IP}"
                    echo "➡ User: ${env.REMOTE_USER}"
                    echo "➡ Key: ${env.PRIVATE_KEY}"
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
                echo "📤 Sending public key to ${params.TARGET_HOST}..."
                sh """
                    ssh-copy-id -i "${env.PUBLIC_KEY}" ${env.REMOTE_USER}@${env.TARGET_IP} || true
                """
            }
        }

        stage('Test SSH Connection') {
            steps {
                script {
                    def result = sh(script: """
                        ssh -o StrictHostKeyChecking=no -i ${env.PRIVATE_KEY} ${env.REMOTE_USER}@${env.TARGET_IP} 'echo OK'
                    """, returnStatus: true)

                    if (result != 0) {
                        error "❌ Cannot connect to ${params.TARGET_HOST} via SSH."
                    } else {
                        echo "✅ SSH connection successful."
                    }
                }
            }
        }

        stage('Run Ansible Playbook') {
            steps {
                echo "🚀 Running playbook: ${params.PLAYBOOK} on ${params.TARGET_HOST}"
                sh """
                    ansible-playbook -i ${INVENTORY_FILE} playbooks/${params.PLAYBOOK} --limit ${params.TARGET_HOST}
                """
            }
        }
    }
}
