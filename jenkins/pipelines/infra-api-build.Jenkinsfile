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
        disableConcurrentBuilds()
        timeout(time: 25, unit: 'MINUTES')
    }

    environment {
        CFG_HARBOR_HOST = "${env.HARBOR_HOST}"
        CFG_HARBOR_PROJECT_NAME = "${env.HARBOR_PROJECT_NAME}"
        CFG_HARBOR_REPOSITORY_NAME = "${env.HARBOR_REPOSITORY_NAME}"
    }

    stages {
        stage('Checkout') {
            steps {
                banner('Checkout repository', '34')
                checkout scm
            }
        }

        stage('Install dependencies') {
            steps {
                banner('Install Python dependencies', '34')
                sh '''
                    python -m venv .venv
                    . .venv/bin/activate
                    python -m pip install --upgrade pip
                    pip install -r homelab-api/app/requirements.txt
                    pip install pytest
                '''
            }
        }

        stage('Run tests') {
            when {
                expression { return params.RUN_TESTS }
            }
            steps {
                banner('Run pytest', '32')
                sh '''
                    . .venv/bin/activate
                    if [ -d homelab-api/tests ]; then
                        pytest -q homelab-api/tests
                    else
                        echo "No tests directory found, skipping"
                    fi
                '''
            }
        }

        stage('Syntax check') {
            steps {
                banner('Python syntax check', '36')
                sh '''
                    . .venv/bin/activate
                    python -m py_compile homelab-api/app/main.py
                '''
            }
        }

        stage('Build and publish image') {
            when {
                expression { return params.PUBLISH_IMAGE }
            }
            steps {
                banner('Publishing image to Harbor', '35')
                withCredentials([
                    usernamePassword(
                        credentialsId: 'harbor-my-creds',
                        usernameVariable: 'HARBOR_OWNER_USER',
                        passwordVariable: 'HARBOR_OWNER_PASS'
                    ),
                    usernamePassword(
                        credentialsId: 'harbor-jenkins-creds',
                        usernameVariable: 'HARBOR_USER',
                        passwordVariable: 'HARBOR_PASS'
                    )
                ]) {
                    container('py') {
                        sh '''
                            set -eu
                            if [ -z "${HARBOR_OWNER_USER:-}" ] || [ -z "${HARBOR_OWNER_PASS:-}" ]; then
                                echo "ERROR: Jenkins credential harbor-my-creds is missing or empty."
                                exit 1
                            fi

                            if [ -z "${HARBOR_USER:-}" ] || [ -z "${HARBOR_PASS:-}" ]; then
                                echo "ERROR: Jenkins credential harbor-jenkins-creds is missing or empty."
                                echo "Set harbor-jenkins-username and harbor-jenkins-password in jenkins-secrets and restart Jenkins."
                                exit 1
                            fi
                            python3 jenkins/scripts/harbor_prepare.py
                        '''
                    }
                    container('kaniko') {
                        sh '''
                            set -eu
                            . ./.harbor_env
                            BUILD_CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

                            mkdir -p /kaniko/.docker
                            cat > /kaniko/.docker/config.json <<EOF
                            {
                              "auths": {
                                "$REGISTRY_HOST": {
                                  "username": "$HARBOR_USER",
                                  "password": "$HARBOR_PASS"
                                }
                              }
                            }
                            EOF

                            /kaniko/executor \
                              --context "$WORKSPACE/homelab-api" \
                              --dockerfile "$WORKSPACE/homelab-api/Dockerfile" \
                              --destination "$DEST_REPO:$IMAGE_TAG" \
                              --skip-tls-verify-registry "$REGISTRY_HOST" \
                              --label "org.opencontainers.image.source=https://github.com/Kobeep/home_infra" \
                              --label "org.opencontainers.image.revision=${GIT_COMMIT:-unknown}" \
                              --label "org.opencontainers.image.created=${BUILD_CREATED_AT}" \
                              --snapshot-mode=redo \
                              --use-new-run
                        '''
                    }
                    container('py') {
                        sh '''
                            set -eu
                            set -a
                            . ./.harbor_env
                            set +a
                            python3 jenkins/scripts/harbor_verify.py
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            banner('infra-api pipeline completed successfully', '32')
        }
        failure {
            banner('infra-api pipeline failed', '31')
        }
    }
}
