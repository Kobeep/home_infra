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

                            python3 - <<'PY'
import json
import os
import ssl
import urllib.request
import urllib.error
import urllib.parse

def norm(v: str) -> str:
    if v is None:
        return ''
    vv = str(v).strip()
    if vv.lower() in ('', 'null', 'none'):
        return ''
    return vv

owner_user = norm(os.getenv('HARBOR_OWNER_USER'))
owner_pass = norm(os.getenv('HARBOR_OWNER_PASS'))
project_name = norm(os.getenv('PROJECT_NAME')) or norm(os.getenv('CFG_HARBOR_PROJECT_NAME')) or 'home-infra'
repository_name = norm(os.getenv('REPOSITORY_NAME')) or norm(os.getenv('CFG_HARBOR_REPOSITORY_NAME')) or 'infra-api'
host_value = norm(os.getenv('HARBOR_HOST_OVERRIDE')) or norm(os.getenv('CFG_HARBOR_HOST'))
repo_override = norm(os.getenv('IMAGE_REPO'))
image_tag = norm(os.getenv('IMAGE_TAG')) or 'latest'

if not host_value and repo_override:
    host_value = repo_override.split('/')[0]

if not host_value:
    raise SystemExit('ERROR: Harbor host is not set. Configure HARBOR_HOST in jenkins-secrets or pass HARBOR_HOST_OVERRIDE/IMAGE_REPO.')
if not project_name:
    raise SystemExit('ERROR: PROJECT_NAME is empty.')
if not repository_name:
    raise SystemExit('ERROR: REPOSITORY_NAME is empty.')

if repo_override:
    dest_repo = repo_override
else:
    dest_repo = f"{host_value}/{project_name}/{repository_name}"

ctx = ssl._create_unverified_context()

def call(method: str, path: str, body=None):
    url = f"https://{host_value}{path}"
    req = urllib.request.Request(url=url, method=method)
    creds = f"{owner_user}:{owner_pass}".encode('utf-8')
    auth = 'Basic ' + __import__('base64').b64encode(creds).decode('ascii')
    req.add_header('Authorization', auth)
    if body is not None:
        data = json.dumps(body).encode('utf-8')
        req.add_header('Content-Type', 'application/json')
    else:
        data = None
    try:
        with urllib.request.urlopen(req, data=data, context=ctx) as resp:
            raw = resp.read().decode('utf-8')
            return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode('utf-8')
        return e.code, raw

code, payload = call('GET', f"/api/v2.0/projects/{urllib.parse.quote(project_name, safe='')}")
if code == 404:
    c2, p2 = call('POST', '/api/v2.0/projects', {'project_name': project_name, 'metadata': {'public': 'false'}})
    if c2 not in (201, 409):
        raise SystemExit(f"ERROR: Harbor project bootstrap failed with HTTP {c2}. Payload: {p2}")
elif code != 200:
    raise SystemExit(f"ERROR: Harbor project check failed with HTTP {code}. Payload: {payload}")

env_lines = [
    f"DEST_REPO={dest_repo}",
    f"REGISTRY_HOST={host_value}",
    f"PROJECT_NAME={project_name}",
    f"REPOSITORY_NAME={repository_name}",
    f"IMAGE_TAG={image_tag}",
]
with open('.harbor_env', 'w', encoding='utf-8') as f:
    for line in env_lines:
        print(line, file=f)

print(f"Pushing image to {dest_repo}:{image_tag}")
PY
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
                            . ./.harbor_env
                            python3 - <<'PY'
import base64
import os
import ssl
import urllib.request
import urllib.error
import urllib.parse

owner_user = os.getenv('HARBOR_OWNER_USER', '')
owner_pass = os.getenv('HARBOR_OWNER_PASS', '')
host_value = os.getenv('REGISTRY_HOST', '')
project_name = os.getenv('PROJECT_NAME', '')
repository_name = os.getenv('REPOSITORY_NAME', '')
image_tag = os.getenv('IMAGE_TAG', '')

ctx = ssl._create_unverified_context()
auth = 'Basic ' + base64.b64encode(f"{owner_user}:{owner_pass}".encode('utf-8')).decode('ascii')

repo_path = urllib.parse.quote(repository_name, safe='')
checks = [
    (f"/api/v2.0/projects/{urllib.parse.quote(project_name, safe='')}/repositories/{repo_path}", 'repository'),
    (f"/api/v2.0/projects/{urllib.parse.quote(project_name, safe='')}/repositories/{repo_path}/artifacts/{urllib.parse.quote(image_tag, safe='')}", 'artifact'),
]

for path, kind in checks:
    url = f"https://{host_value}{path}"
    req = urllib.request.Request(url=url, method='GET')
    req.add_header('Authorization', auth)
    try:
        with urllib.request.urlopen(req, context=ctx) as resp:
            if resp.status != 200:
                raise SystemExit(f"ERROR: Harbor {kind} verification failed with HTTP {resp.status} for {url}")
    except urllib.error.HTTPError as e:
        payload = e.read().decode('utf-8')
        raise SystemExit(f"ERROR: Harbor {kind} verification failed with HTTP {e.code} for {url}. Payload: {payload}")

print(f"Harbor verification passed: https://{host_value}/harbor/projects/{project_name}/repositories/{repository_name}/artifacts-tab")
PY
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
