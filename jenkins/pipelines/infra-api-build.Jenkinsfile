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
                banner("Publishing ${params.IMAGE_REPO}:${params.IMAGE_TAG}", '35')
                withCredentials([
                    usernamePassword(
                        credentialsId: 'harbor-jenkins-creds',
                        usernameVariable: 'HARBOR_USER',
                        passwordVariable: 'HARBOR_PASS'
                    )
                ]) {
                    container('kaniko') {
                        sh '''
                            set -eu
                            REGISTRY_HOST=$(echo "$IMAGE_REPO" | cut -d/ -f1)
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
                              --destination "$IMAGE_REPO:$IMAGE_TAG" \
                              --snapshot-mode=redo \
                              --use-new-run
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
