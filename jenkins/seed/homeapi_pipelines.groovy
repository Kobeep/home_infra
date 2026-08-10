pipelineJob('infra-api-build') {
    description('Build/test/publish pipeline for the infra-api project (homelab-api).')

    parameters {
        stringParam('PYTHON_VERSION', '3.11', 'Python version used by the build container.')
        booleanParam('RUN_TESTS', true, 'Run pytest tests.')
        booleanParam('PUBLISH_IMAGE', true, 'Publish the image to Harbor.')
        stringParam('IMAGE_REPO', 'harbor.192.168.1.16.nip.io/home_infra/infra-api', 'Image repository (without tag). Use your Harbor host and project path.')
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
        stringParam('SERVER_IP', '', 'Optional k3s host IP/DNS override. Leave empty to use ansible_host from inventory.')
        stringParam('PLAYBOOK', 'ansible/playbooks/full-setup.yml', 'Playbook path to run.')
        textParam('ANSIBLE_VAULT_PASSWORD', '', 'Optional Ansible Vault password textbox. Leave empty to use Jenkins credential ansible-vault-password.')
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
