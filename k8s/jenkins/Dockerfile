# JCASC + plugins
FROM jenkins/jenkins:lts

USER root

RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

USER jenkins

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    CASC_JENKINS_CONFIG="/usr/share/jenkins/ref/casc.yaml"

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/ref/casc.yaml
COPY --chown=jenkins:jenkins config.xml /usr/share/jenkins/ref/config.xml

EXPOSE 8080 50000

ENTRYPOINT ["sh", "-c", "jenkins-plugin-cli --jenkins-update-center https://updates.jenkins.io/update-center.json -f /usr/share/jenkins/ref/plugins.txt && exec /usr/bin/tini -- /usr/local/bin/jenkins.sh"]
