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
        IPaddress = "${env.IPaddress}"
        DeploymentName = "${params.DeploymentName}"
        PodName = "${params.PodName}"
        Namespace = "${params.Namespace}"
        Action = "${params.Action}"
    }

    stages {
        stage('Checkout') {
            steps {
                banner('Checkout repository', '34')
                checkout scm
            }
        }

        stage('Updates') {
            steps {
                banner('Install updates', '34')
                sh '''
                    apt-get update -y
                '''
            }
        }

        stage('Run API Trigger') {
            steps {
                banner("Triggering action ${params.Action} on ${if (params.DeploymentName) {echo "deployment " + params.DeploymentName } elif { echo "pod " + params.PodName } else { echo "cluster" }} in namespace ${params.Namespace}", '33')
                sh '''
                    #!/bin/bash
                    set -euo pipefail

                    if [[ -n "${DeploymentName}" ]]; then
                        echo "Triggering action ${Action} on deployment ${DeploymentName} in namespace ${Namespace}"
                        curl -X POST "https://${IPaddress}.nip.io/api/kubernetes/${Action}/${DeploymentName}/${Namespace}"
                    elif [[ -n "${PodName}" ]]; then
                        echo "Triggering action ${Action} on pod ${PodName} in namespace ${Namespace}"
                        curl -X POST "https://${IPaddress}.nip.io/api/kubernetes/${Action}/${PodName}/${Namespace}"
                    elif [[ "${Action}" == "clean-cluster" ]]; then
                        echo "Triggering action ${Action} on the cluster"
                        curl -X POST "https://${IPaddress}.nip.io/api/kubernetes/${Action}"
                    else
                        echo "No DeploymentName or PodName provided. Exiting."
                        exit 1
                    fi
                '''
            }
        }

        post {
        success {
            banner('Action completed successfully', '32')
        }
        failure {
            banner('Action failed', '31')
        }
    }
    }
