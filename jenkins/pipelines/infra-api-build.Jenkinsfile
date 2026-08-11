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
                    container('kaniko') {
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

                            PROJECT_NAME="${PROJECT_NAME:-${HARBOR_PROJECT_NAME:-home-infra}}"
                            REPOSITORY_NAME="${REPOSITORY_NAME:-${HARBOR_REPOSITORY_NAME:-infra-api}}"
                            HARBOR_HOST_VALUE="${HARBOR_HOST:-}"
                            IMAGE_REPO_OVERRIDE="${IMAGE_REPO:-}"

                            if [ -z "$PROJECT_NAME" ]; then
                                echo "ERROR: PROJECT_NAME is empty."
                                exit 1
                            fi

                            if [ -z "$REPOSITORY_NAME" ]; then
                                echo "ERROR: REPOSITORY_NAME is empty."
                                exit 1
                            fi

                            if [ -z "$HARBOR_HOST_VALUE" ] && [ -n "$IMAGE_REPO_OVERRIDE" ]; then
                                HARBOR_HOST_VALUE="$(echo "$IMAGE_REPO_OVERRIDE" | cut -d/ -f1)"
                            fi

                            if [ -z "$HARBOR_HOST_VALUE" ]; then
                                echo "ERROR: Harbor host is not set. Configure HARBOR_HOST in jenkins-secrets or pass IMAGE_REPO override."
                                exit 1
                            fi

                            if [ -n "$IMAGE_REPO_OVERRIDE" ]; then
                                DEST_REPO="$IMAGE_REPO_OVERRIDE"
                            else
                                DEST_REPO="${HARBOR_HOST_VALUE}/${PROJECT_NAME}/${REPOSITORY_NAME}"
                            fi

                            PROJECT_CODE="$(curl -ks -o /tmp/harbor-project-check.out -w '%{http_code}' -u "${HARBOR_OWNER_USER}:${HARBOR_OWNER_PASS}" "https://${HARBOR_HOST_VALUE}/api/v2.0/projects/${PROJECT_NAME}")"
                            if [ "$PROJECT_CODE" = "404" ]; then
                                CREATE_CODE="$(curl -ks -o /tmp/harbor-project-create.out -w '%{http_code}' \
                                  -u "${HARBOR_OWNER_USER}:${HARBOR_OWNER_PASS}" \
                                  -H 'Content-Type: application/json' \
                                  -X POST "https://${HARBOR_HOST_VALUE}/api/v2.0/projects" \
                                  -d "{\"project_name\":\"${PROJECT_NAME}\",\"metadata\":{\"public\":\"false\"}}")"
                                if [ "$CREATE_CODE" != "201" ] && [ "$CREATE_CODE" != "409" ]; then
                                    echo "ERROR: Harbor project bootstrap failed with HTTP ${CREATE_CODE}."
                                    cat /tmp/harbor-project-create.out
                                    exit 1
                                fi
                            elif [ "$PROJECT_CODE" != "200" ]; then
                                echo "ERROR: Harbor project check failed with HTTP ${PROJECT_CODE}."
                                cat /tmp/harbor-project-check.out
                                exit 1
                            fi

                            echo "Pushing image to ${DEST_REPO}:${IMAGE_TAG}"

                            REGISTRY_HOST="$(echo "$DEST_REPO" | cut -d/ -f1)"
                            REPO_NAME="$(echo "$DEST_REPO" | cut -d/ -f3-)"
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

                                                        REPO_CODE="$(curl -ks -o /tmp/harbor-repo-check.out -w '%{http_code}' \
                                                            -u "${HARBOR_OWNER_USER}:${HARBOR_OWNER_PASS}" \
                                                            "https://${HARBOR_HOST_VALUE}/api/v2.0/projects/${PROJECT_NAME}/repositories/${REPO_NAME}")"
                                                        if [ "$REPO_CODE" != "200" ]; then
                                                                echo "ERROR: Harbor repository verification failed for ${PROJECT_NAME}/${REPO_NAME} (HTTP ${REPO_CODE})."
                                                                cat /tmp/harbor-repo-check.out
                                                                exit 1
                                                        fi

                                                        ARTIFACT_CODE="$(curl -ks -o /tmp/harbor-artifact-check.out -w '%{http_code}' \
                                                            -u "${HARBOR_OWNER_USER}:${HARBOR_OWNER_PASS}" \
                                                            "https://${HARBOR_HOST_VALUE}/api/v2.0/projects/${PROJECT_NAME}/repositories/${REPO_NAME}/artifacts/${IMAGE_TAG}")"
                                                        if [ "$ARTIFACT_CODE" != "200" ]; then
                                                                echo "ERROR: Harbor artifact tag verification failed for ${PROJECT_NAME}/${REPO_NAME}:${IMAGE_TAG} (HTTP ${ARTIFACT_CODE})."
                                                                cat /tmp/harbor-artifact-check.out
                                                                exit 1
                                                        fi

                                                        echo "Harbor verification passed: https://${HARBOR_HOST_VALUE}/harbor/projects/${PROJECT_NAME}/repositories/${REPO_NAME}/artifacts-tab"
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
