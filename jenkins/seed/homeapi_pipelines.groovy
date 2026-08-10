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
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/Kobeep/home_infra.git')
                    }
                    branches('*/main')
                }
            }
            scriptPath('jenkins/pipelines/infra-api-build.Jenkinsfile')
            lightweight(true)
        }
    }

    logRotator {
        numToKeep(30)
    }
}

pipelineJob('k3s-ansible-playbook') {
    description('Runs ansible-playbook on the k3s host via SSH with colored output.')

    parameters {
        stringParam('SERVER_IP', '127.0.0.1', 'k3s host IP or DNS name.')
        stringParam('PLAYBOOK', 'ansible/playbooks/full-setup.yml', 'Playbook path to run.')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/Kobeep/home_infra.git')
                    }
                    branches('*/main')
                }
            }
            scriptPath('jenkins/pipelines/k3s-ansible-playbook.Jenkinsfile')
            lightweight(true)
        }
    }

    logRotator {
        numToKeep(30)
    }
}

pipelineJob('home-api-get-checks') {
    description('Sends GET requests to home-api and validates HTTP statuses.')

    parameters {
        stringParam('BASE_URL', 'https://api.127.0.0.1.nip.io', 'Base API URL without trailing slash.')
        textParam('ENDPOINTS', '/health\n/docs', 'Endpoint list, one per line, e.g. /health')
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url('https://github.com/Kobeep/home_infra.git')
                    }
                    branches('*/main')
                }
            }
            scriptPath('jenkins/pipelines/home-api-get-checks.Jenkinsfile')
            lightweight(true)
        }
    }

    logRotator {
        numToKeep(30)
    }
}
