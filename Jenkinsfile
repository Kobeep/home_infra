pipeline {
    agent any

    environment {
        INVENTORY_FILE = 'ansible/inventories/hosts.yml'
        PLAYBOOKS_DIR  = 'ansible/playbooks'
    }

    stages {
        stage('Checkout Repository') {
            steps {
                echo "📥 Checking out source code..."
                checkout scm
            }
        }

        stage('Dynamic Host & Playbook Selection') {
            steps {
                script {
                    def inv = readYaml file: "${env.INVENTORY_FILE}"
                    def hosts = inv.all.hosts.keySet().toList()

                    def playbooksShell = sh(
                        script: "ls ${env.PLAYBOOKS_DIR}/*.yml | xargs -n1 basename",
                        returnStdout: true
                    ).trim()
                    def playbooks = playbooksShell.tokenize("\n")

                    def userSelection = input(
                        message: 'Select target host and playbook:',
                        parameters: [
                            [
                                $class: 'ChoiceParameterDefinition',
                                choices: hosts.join("\n"),
                                description: 'Choose the target host',
                                name: 'TARGET_HOST'
                            ],
                            [
                                $class: 'ChoiceParameterDefinition',
                                choices: playbooks.join("\n"),
                                description: 'Choose the playbook to run',
                                name: 'PLAYBOOK'
                            ]
                        ]
                    )

                    env.TARGET_HOST = userSelection.TARGET_HOST
                    env.PLAYBOOK    = userSelection.PLAYBOOK

                    echo "Selected host: ${env.TARGET_HOST}"
                    echo "Selected playbook: ${env.PLAYBOOK}"
                }
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
    print(json.dumps(inv["all"]["hosts"]["${env.TARGET_HOST}"]))
                        '
                    """, returnStdout: true).trim()

                    def hostConfig = readJSON text: inventoryJson

                    env.TARGET_IP   = hostConfig.ansible_host
                    env.REMOTE_USER = hostConfig.ansible_user
                    env.PRIVATE_KEY = hostConfig.ansible_ssh_private_key_file
                    env.PUBLIC_KEY  = "${env.PRIVATE_KEY}.pub"

                    echo "➡ Host: ${env.TARGET_HOST}"
                    echo "➡ IP: ${env.TARGET_IP}"
                    echo "➡ Remote user: ${env.REMOTE_USER}"
                    echo "➡ Private key path: ${env.PRIVATE_KEY}"
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
                    def sshPassword = input(
                        message: "Enter SSH password for host ${env.TARGET_HOST}:",
                        parameters: [password(name: 'SSH_PASS', defaultValue: '', description: 'SSH Password')]
                    )
                    env.SSH_PASS = sshPassword

                    echo "📤 Sending public key to ${env.TARGET_HOST}..."
                    sh """
                        sshpass -p "${env.SSH_PASS}" ssh-copy-id -i "${env.PUBLIC_KEY}" ${env.REMOTE_USER}@${env.TARGET_IP} || true
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
                        error "❌ ERROR: Cannot connect to ${env.TARGET_HOST} via SSH."
                    } else {
                        echo "✅ SSH connection successful."
                    }
                }
            }
        }

        stage('Run Ansible Playbook') {
            steps {
                echo "🚀 Running playbook: ${env.PLAYBOOK} on host ${env.TARGET_HOST}"
                sh """
                    ansible-playbook -i ${INVENTORY_FILE} ${env.PLAYBOOKS_DIR}/${env.PLAYBOOK} --limit ${env.TARGET_HOST}
                """
            }
        }
    }
}
