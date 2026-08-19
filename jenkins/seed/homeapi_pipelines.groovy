import groovy.json.JsonSlurper

pipelineJob('k3s-api-trigger') {
    description('Allows executing a specific API endpoint on the home-api service running in the k3s cluster. Useful for triggering actions like rollouts or pod restarts.')

    environmentVariables {
        env('IPaddress', getJenkinsHostIp())
    }

    parameters {
        choiceParam('TargetType', ['Deployment', 'Pod', 'Cluster'], 'Select what type of resource to target.')
        stringParam('DeploymentName', '', 'The name of the deployment to trigger the action on (if TargetType is Deployment).')
        stringParam('PodName', '', 'The name of the pod to trigger the action on (if TargetType is Pod).')
        choiceParam('Action', ['kill', 'rollout', 'scale', 'exec', 'clean-cluster'], 'Pick the action to perform.')
        stringParam('Namespace', 'default', 'Optional namespace override.')
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
            scriptPath('jenkins/pipelines/k3s-api-trigger.Jenkinsfile')
            lightweight(true)
        }
    }

    logRotator {
        numToKeep(30)
    }
}

pipelineJob('infra-api-build') {
    description('Build/test/publish pipeline for the infra-api project (homelab-api).')

    parameters {
        stringParam('PYTHON_VERSION', '3.11', 'Python version used by the build container.')
        booleanParam('RUN_TESTS', true, 'Run pytest tests.')
        booleanParam('PUBLISH_IMAGE', true, 'Publish the image to Harbor.')
        stringParam('PROJECT_NAME', '', 'Harbor project name. Leave empty to use HARBOR_PROJECT_NAME from Jenkins environment.')
        stringParam('REPOSITORY_NAME', '', 'Harbor repository name. Leave empty to use HARBOR_REPOSITORY_NAME from Jenkins environment.')
        stringParam('HARBOR_HOST_OVERRIDE', '', 'Optional Harbor host override, e.g. harbor.192.168.1.16.nip.io. Leave empty to use HARBOR_HOST from Jenkins environment.')
        stringParam('IMAGE_REPO', '', 'Optional full repository override, e.g. harbor.host/project/infra-api. Leave empty for automatic harbor/<project>/infra-api.')
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
        stringParam('BASE_URL', "https://api.${getJenkinsHostIp()}.nip.io", 'Base API URL without trailing slash.')
        textParam('AVAILABLE_ENDPOINTS', getListOfApiEndpoints().join('\n'))
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
// call homeapi /api to get list of endpoints and add them to the ENDPOINTS parameter
def getListOfApiEndpoints() {
    try {
        def baseUrl = "https://api.${getJenkinsHostIp()}.nip.io/api"
        def responseText = baseUrl.toURL().text
        def jsonResponse = new JsonSlurper().parseText(responseText)
        return jsonResponse.collect { it.path }
    } catch (Exception e) {
        println "Couldnt fetch endpoints: ${e.message}"
        return []
    }
}

// check hostname for jenkins to fetch the IP for the API URL
def getJenkinsHostIp() {
    def hostname = "hostname".execute().text.trim()
    def ipAddress = ["sh", "-c", "getent hosts ${hostname} | awk '{print \$1}'"].execute().text.trim()
    return ipAddress ?: "127.0.0.1"
}
