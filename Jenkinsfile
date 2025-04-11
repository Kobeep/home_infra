pipeline {
    agent { label 'slave' }

    parameters {
        string(name: 'TARGET_HOST', defaultValue: '', description: 'Target host from inventory')
        string(name: 'PLAYBOOK', defaultValue: '', description: 'Playbook to run')
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
                echo "📥 Checking out repository for deployment..."
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

                    env.TARGET_IP   = hostConfig.ansible_host
                    env.REMOTE_USER = hostConfig.ansible_user
                    env.PRIVATE_KEY = "${SSH_BASE_DIR}/${params.TARGET_HOST}/id_rsa"
                    env.PUBLIC_KEY  = "${env.PRIVATE_KEY}.pub"

                    echo "➡ Host: ${params.TARGET_HOST}"
                    echo "➡ IP: ${env.TARGET_IP}"
                    echo "➡ Remote user: ${env.REMOTE_USER}"
                    echo "➡ Private key: ${env.PRIVATE_KEY}"
                }
            }
        }

        stage('Ensure SSH Key Exists') {
          steps {
              script {
                  def keyExists = sh(script: "[ -f '${env.PRIVATE_KEY}' ] && echo yes || echo no", returnStdout: true).trim()

                  if (keyExists == "no") {
                      echo "🔑 SSH key not found in ${env.PRIVATE_KEY}. Generating..."
                      sh """
                          mkdir -p \$(dirname "${env.PRIVATE_KEY}")
                          ssh-keygen -t rsa -b 4096 -f "${env.PRIVATE_KEY}" -N ''
                          chmod 600 "${env.PRIVATE_KEY}"
                      """
                      echo "📤 Sending public key to ${params.TARGET_HOST}..."
                      sh """
                          sshpass -p "${params.SSH_PASS}" ssh-copy-id -i "${env.PUBLIC_KEY}" ${env.REMOTE_USER}@${env.TARGET_IP} || true
                      """
                  } else {
                      echo "✅ SSH key already exists."
                      sh "chmod 600 ${env.PRIVATE_KEY}"
                  }
              }
          }
        }

        stage('Test SSH Connection') {
            steps {
                script {
                    def sshTest = sh(script: """
                        ssh -o StrictHostKeyChecking=no -i ${env.PRIVATE_KEY} ${env.REMOTE_USER}@${env.TARGET_IP} 'echo OK'
                    """, returnStatus: true)

                    if (sshTest != 0) {
                        error "❌ ERROR: Unable to establish SSH connection to ${params.TARGET_HOST}."
                        sh """
                          rm -rfv /var/jenkins_home/.ssh/${params.TARGET_HOST}
                        """
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
                    cd ansible
                    sshpass -p "${params.SSH_PASS}" ansible-playbook -i ./inventories/hosts.yml ./playbooks/${params.PLAYBOOK} -K  --limit ${params.TARGET_HOST} || true
                """
            }
        }
    }
}
