def branches = ['main', 'develop']

branches.each { pipeline ->

    pipelineJob("home_infra-${pipeline}") {
        description("Generate pipeline for branch: ${pipeline} (Generated automatically by upstream.groovy)")

        definition {
            cpsScm {
                scm {
                    git {
                        remote {
                            url("https://github.com/Kobeep/home_infra.git")
                            credentials('github')
                        }
                        branches("*/${pipeline}")
                    }
                }
                scriptPath('jenkins/Jenkinsfile')
                lightweight(true)
            }
        }

        logRotator {
            numToKeep(10)
            daysToKeep(7)
        }
    }
}
