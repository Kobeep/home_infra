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
        disableConcurrentBuilds()
        timeout(time: 10, unit: 'MINUTES')
    }

    stages {
        stage('GET checks') {
            steps {
                banner("Checking API at ${params.BASE_URL}", '34')
                sh '''
                    set -eu
                    echo "$ENDPOINTS" | while IFS= read -r endpoint; do
                        [ -z "$endpoint" ] && continue
                        url="$BASE_URL$endpoint"

                        code=$(curl -k -sS -o /tmp/resp_body -w "%{http_code}" "$url")
                        if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
                            printf "\\033[1;32m[OK]\\033[0m GET %s -> %s\\n" "$url" "$code"
                        else
                            printf "\\033[1;31m[FAIL]\\033[0m GET %s -> %s\\n" "$url" "$code"
                            echo "--- response body ---"
                            cat /tmp/resp_body || true
                            exit 1
                        fi
                    done
                '''
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
