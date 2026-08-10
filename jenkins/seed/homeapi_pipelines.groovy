def commonPipelineHeader = '''def banner(String msg, String color = '36') {
    echo "\\u001B[1;${color}m===> ${msg}\\u001B[0m"
}
'''

pipelineJob('infra-api-build') {
    description('Build/test/publish pipeline for the infra-api project (homelab-api).')

    parameters {
        stringParam('PYTHON_VERSION', '3.11', 'Python version used by the build container.')
        booleanParam('RUN_TESTS', true, 'Run pytest tests.')
        booleanParam('PUBLISH_IMAGE', true, 'Publish the image to Harbor.')
        stringParam('IMAGE_REPO', 'harbor.127.0.0.1.nip.io/library/infra-api', 'Image repository (without tag).')
        stringParam('IMAGE_TAG', 'latest', 'Docker image tag.')
    }

    definition {
        cps {
            script(commonPipelineHeader + '''
pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: py
    image: python:${params.PYTHON_VERSION}
    command: ['cat']
    tty: true
  - name: kaniko
    image: gcr.io/kaniko-project/executor:v1.23.2-debug
    command: ['cat']
    tty: true
"""
            defaultContainer 'py'
        }
    }

    options {
        ansiColor('xterm')
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 25, unit: 'MINUTES')
    }

    stages {
        stage('Checkout') {
            steps {
                banner('Checkout repo', '34')
                checkout scm
            }
        }

        stage('Install deps') {
            steps {
                banner('Install dependencies', '34')
                sh """
                    python -m venv .venv
                    . .venv/bin/activate
                    python -m pip install --upgrade pip
                    pip install -r homelab-api/app/requirements.txt
                    pip install pytest
                """
            }
        }

        stage('Run tests') {
            when {
                expression { return params.RUN_TESTS }
            }
            steps {
                banner('Run pytest for infra-api', '32')
                sh """
                    . .venv/bin/activate
                    if [ -d homelab-api/tests ]; then
                        pytest -q homelab-api/tests
                    else
                        echo "No tests directory found, skipping"
                    fi
                """
            }
        }

        stage('Quick syntax check') {
            steps {
                banner('Python compile check', '36')
                sh """
                    . .venv/bin/activate
                    python -m py_compile homelab-api/app/main.py
                """
            }
        }

        stage('Build and publish image to Harbor') {
            when {
                expression { return params.PUBLISH_IMAGE }
            }
            steps {
                banner("Publishing ${params.IMAGE_REPO}:${params.IMAGE_TAG}", '35')
                withCredentials([
                    usernamePassword(
                        credentialsId: 'harbor-jenkins-creds',
                        usernameVariable: 'HARBOR_USER',
                        passwordVariable: 'HARBOR_PASS'
                    )
                ]) {
                    container('kaniko') {
                        sh """
                            set -eu
                                                        REGISTRY_HOST=\$(echo "\${IMAGE_REPO}" | cut -d/ -f1)
                            mkdir -p /kaniko/.docker

                            cat > /kaniko/.docker/config.json <<EOF
                            {
                              "auths": {
                                                                "\${REGISTRY_HOST}": {
                                                                    "username": "\${HARBOR_USER}",
                                                                    "password": "\${HARBOR_PASS}"
                                }
                              }
                            }
                            EOF

                            /kaniko/executor \
                                                            --context "\${WORKSPACE}/homelab-api" \
                                                            --dockerfile "\${WORKSPACE}/homelab-api/Dockerfile" \
                                                            --destination "\${IMAGE_REPO}:\${IMAGE_TAG}" \
                              --snapshot-mode=redo \
                              --use-new-run
                        """
                    }
                }
            }
        }
    }

    post {
        success {
            banner('infra-api pipeline finished successfully', '32')
        }
        failure {
            banner('infra-api pipeline failed', '31')
        }
    }
}
''')
            sandbox()
        }
    }
}

pipelineJob('k3s-ansible-playbook') {
    description('Runs ansible-playbook on the k3s host (via SSH) with colored output.')

    parameters {
        stringParam('SERVER_IP', '127.0.0.1', 'k3s host IP or DNS name.')
        stringParam('PLAYBOOK', 'ansible/playbooks/full-setup.yml', 'Playbook path to run.')
    }

    definition {
        cps {
            script(commonPipelineHeader + '''
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
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 40, unit: 'MINUTES')
    }

    environment {
        ANSIBLE_FORCE_COLOR = 'true'
    }

    stages {
        stage('Checkout') {
            steps {
                banner('Checkout repo', '34')
                checkout scm
            }
        }

        stage('Install ansible') {
            steps {
                banner('Install ansible tooling', '34')
                sh """
                    apt-get update
                    apt-get install -y --no-install-recommends python3-pip python3-setuptools openssh-client
                    pip3 install --no-cache-dir ansible
                """
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
                        sh """
                            mkdir -p ~/.ssh && chmod 700 ~/.ssh
                                                        ssh-keyscan -H "\${SERVER_IP}" >> ~/.ssh/known_hosts 2>/dev/null || true

                                                        printf "%s" "\$VAULT_PASS" > .vault_pass
                                                        ANSIBLE_ROLES_PATH=ansible/roles ansible-playbook "\${PLAYBOOK}" \
                              -i ansible/inventory.yml \
                              --vault-password-file .vault_pass \
                                                            -e "ansible_user=\${SSH_USER}" \
                                                            -e "ansible_ssh_private_key_file=\${SSH_KEY}" \
                                                            -e "ansible_host=\${SERVER_IP}" \
                              -e "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o PubkeyAcceptedKeyTypes=+ssh-rsa'"
                            rm -f .vault_pass
                        """
                    }
                }
            }
        }
    }

    post {
        success {
            banner('ansible deploy finished successfully', '32')
        }
        failure {
            banner('ansible deploy failed', '31')
        }
    }
}
''')
            sandbox()
        }
    }
}

pipelineJob('home-api-get-checks') {
    description('Sends GET requests to home-api and validates HTTP statuses.')

    parameters {
        stringParam('BASE_URL', 'https://api.127.0.0.1.nip.io', 'Base API URL (without trailing /).')
        textParam('ENDPOINTS', '/health\n/docs', 'Endpoint list (one per line), e.g. /health')
    }

    definition {
        cps {
            script(commonPipelineHeader + '''
pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: curl
    image: curlimages/curl:8.9.1
    command: ['cat']
    tty: true
"""
            defaultContainer 'curl'
        }
    }

    options {
        ansiColor('xterm')
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 10, unit: 'MINUTES')
    }

    stages {
        stage('GET checks') {
            steps {
                banner("Checking API at ${params.BASE_URL}", '34')
                sh """
                    set -eu
                    echo "\$ENDPOINTS" | while IFS= read -r endpoint; do
                        [ -z "\$endpoint" ] && continue
                        url="\${BASE_URL}\${endpoint}"

                        code=\$(curl -k -sS -o /tmp/resp_body -w "%{http_code}" "\$url")
                        if [ "\$code" -ge 200 ] && [ "\$code" -lt 300 ]; then
                            printf "\\033[1;32m[OK]\\033[0m GET %s -> %s\\n" "\$url" "\$code"
                        else
                            printf "\\033[1;31m[FAIL]\\033[0m GET %s -> %s\\n" "\$url" "\$code"
                            echo "--- response body ---"
                            cat /tmp/resp_body || true
                            exit 1
                        fi
                    done
                """
            }
        }
    }

    post {
        success {
            banner('home-api checks passed', '32')
        }
        failure {
            banner('home-api checks failed', '31')
        }
    }
}
''')
            sandbox()
        }
    }
}
