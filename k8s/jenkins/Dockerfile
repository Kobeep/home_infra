FROM jenkins/jenkins:lts

USER root

RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

USER jenkins

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    REF_PLUGINS_FILE="/usr/share/jenkins/ref/plugins.txt" \
    CASC_JENKINS_CONFIG="/var/jenkins_home/casc.yaml"

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/ref/casc.yaml
COPY --chown=jenkins:jenkins config.xml /usr/share/jenkins/ref/config.xml
COPY --chown=jenkins:jenkins jobs/ /usr/share/jenkins/ref/jobs/
COPY --chown=jenkins:jenkins casc.yaml /var/jenkins_home/casc.yaml

EXPOSE 8080
