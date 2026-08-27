# Source the versioned Docker client and its Buildx/Compose CLI plugins without
# carrying a second Docker daemon into the Jenkins agent image.
FROM docker:29.7.2-cli AS docker_cli

# The Docker agent still needs Jenkins Remoting and Java to connect inbound to
# the Controller. JDK 25 keeps the two project-owned agent images consistent.
FROM jenkins/inbound-agent:3386.v353e57a_1b_ea_0-2-jdk25

USER root

COPY --from=docker_cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker_cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

# Git retrieves the source repository and curl supports later registry and
# delivery diagnostics. The agent connects to Docker Desktop through the host
# socket mounted by Compose; no daemon is installed in this image.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*

USER jenkins
