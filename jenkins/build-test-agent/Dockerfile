ARG GITLEAKS_VERSION=8.30.1

FROM ghcr.io/gitleaks/gitleaks:v${GITLEAKS_VERSION} AS gitleaks

# Use the official inbound agent with the same JDK required by the application.
FROM jenkins/inbound-agent:3386.v353e57a_1b_ea_0-2-jdk25

USER root

# Git retrieves the repository, while curl supports later diagnostic and
# pipeline HTTP checks. Gradle is intentionally supplied by the repository's
# versioned wrapper instead of being installed globally in the image.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p \
        /home/jenkins/.dependency-check-data \
        /home/jenkins/.gradle \
    && chown -R jenkins:jenkins \
        /home/jenkins/.dependency-check-data \
        /home/jenkins/.gradle

# Copy the pinned static scanner from its official image instead of installing
# an additional package manager or a complete Go toolchain in the agent.
COPY --from=gitleaks /usr/bin/gitleaks /usr/local/bin/gitleaks

# Build commands must run as the unprivileged user from the upstream image.
USER jenkins
