def banner(String msg, String color = '36') {
    echo "\u001B[1;${color}m===> ${msg}\u001B[0m"
}

pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: shell
    image: ubuntu:22.04
    command: ['cat']
    tty: true
"""
            defaultContainer 'shell'
        }
    }

    options {
        ansiColor('xterm')
        disableConcurrentBuilds()
        timeout(time: 40, unit: 'MINUTES')
    }

    environment {
        ANSIBLE_FORCE_COLOR = 'true'
    }

    stages {
        stage('Checkout') {
            steps {
                banner('Checkout repository', '34')
                checkout scm
            }
        }

        stage('Install ansible') {
            steps {
                banner('Install ansible tooling', '34')
                sh '''
                    apt-get update
                    apt-get install -y --no-install-recommends python3-pip python3-setuptools openssh-client
                    pip3 install --no-cache-dir ansible
                '''
            }
        }

        stage('Run playbook on k3s host') {
            steps {
                banner("Running ${params.PLAYBOOK} on ${params.SERVER_IP}", '33')
                sshagent(credentials: ['serwer-ssh-key']) {
                    withCredentials([
                        sshUserPrivateKey(credentialsId: 'serwer-ssh-key', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER'),
                        string(credentialsId: 'ansible-vault-password', variable: 'VAULT_PASS')
                    ]) {
                        sh '''
                            set -eu
                            mkdir -p ~/.ssh && chmod 700 ~/.ssh
                            ssh-keyscan -H "$SERVER_IP" >> ~/.ssh/known_hosts 2>/dev/null || true

                            VAULT_VALUE="${ANSIBLE_VAULT_PASSWORD:-}"
                            if [ -z "$VAULT_VALUE" ]; then
                                VAULT_VALUE="$VAULT_PASS"
                            fi

                            if [ -z "$VAULT_VALUE" ]; then
                                echo "ERROR: Missing Ansible Vault password. Fill ANSIBLE_VAULT_PASSWORD textbox or configure ansible-vault-password credential."
                                exit 1
                            fi

                            printf "%s" "$VAULT_VALUE" | sed -e 's/[[:space:]]*$//' > .vault_pass
                            ANSIBLE_ROLES_PATH=ansible/roles ansible-playbook "$PLAYBOOK" \
                              -i ansible/inventory.yml \
                              --vault-password-file .vault_pass \
                              -e "ansible_user=$SSH_USER" \
                              -e "ansible_ssh_private_key_file=$SSH_KEY" \
                              -e "ansible_host=$SERVER_IP" \
                              -e "ansible_ssh_common_args=-o StrictHostKeyChecking=accept-new -o PubkeyAcceptedKeyTypes=+ssh-rsa"
                            rm -f .vault_pass
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            banner('ansible deployment completed successfully', '32')
        }
        failure {
            banner('ansible deployment failed', '31')
        }
    }
}
