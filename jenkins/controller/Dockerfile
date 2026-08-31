# Pin the Jenkins LTS release so rebuilding the local controller is predictable.
FROM jenkins/jenkins:2.568.2-jdk21

# Preinstall the baseline plugins required by the Jenkins learning track.
# Runtime configuration remains manual in Phase 13; JCasC starts in Phase 14.
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Bake the declarative Controller configuration into the immutable image. Its
# secret placeholders are resolved only from runtime environment variables.
COPY --chown=jenkins:jenkins jenkins.yaml /usr/share/jenkins/ref/jenkins.yaml
