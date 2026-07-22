def namesPipelines = ['kubectl-functions', 'api-requests']

namesPipelines.each { pipeline ->

    pipelineJob(pipeline) {
        description("Generate pipeline: ${pipeline} (Generated automatically by upstream.groovy)")

        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url("https://github.com/Kobeep/home_infra.git")
                            credentials('github')
                        }
                        branches('*/main')
                    }
                }
                scriptPath('jenkins/Jenkinsfile')
                lightweight(true)
            }
        }

        if (pipeline == 'kubectl-functions') {
            parameters {
                stringParam('KUBECTL_COMMAND', '', 'Command to execute with kubectl')
                stringParam('KUBECTL_NAMESPACE', '', 'Namespace for the kubectl command')
            }
        } else if (pipeline == 'api-requests') {
            parameters {
                stringParam('API_ENDPOINT', "api.${get_ip_address()}.nip.io", 'API endpoint to send requests to. Replace "default" with your cluster IP.')
                stringParam('API_REQUEST', 'pods/deployments/ingresses', 'Payload for the API request')
            }
        }

        logRotator {
            numToKeep(10)
            daysToKeep(7)
        }
    }
}

def get_ip_address() {
    try {
        return java.net.InetAddress.getLocalHost().getHostAddress()
    } catch (Exception e) {
        return "127.0.0.1"
    }
}
