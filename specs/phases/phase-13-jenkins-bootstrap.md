# Spec: Phase 13 - Jenkins Bootstrap

## 1. Goal

Introduce Jenkins as the project's second, independent CI/CD platform, running as a Controller plus two static build agents (Build/Test Agent and Docker Agent), all containerized with Docker Compose and configured with persistent storage so the setup survives container restarts.

## 2. Scope

In scope:

- Jenkins Controller running as a Docker container, with a persistent `jenkins_home` volume
- Build/Test Agent (static), containerized, with JDK, Gradle, and Git installed
- Docker Agent (static), containerized, with Docker and Git installed
- registering both agents with the Controller over the JNLP/inbound-agent protocol
- installing the baseline set of Jenkins plugins required for later phases (Git, Pipeline, Credentials Binding, Docker Pipeline, Configuration as Code)
- a Docker Compose file that starts the Controller and both agents together as one local stack

Out of scope:

- Jenkins Configuration as Code (JCasC) and Multibranch Pipeline setup (Phase 14)
- any actual CI pipeline logic — build, test, or security stages (Phase 15)
- Docker image scanning and artifact publishing (Phase 16)
- deployment to GCP from Jenkins (Phase 17)
- dynamic/on-demand agents (deliberately out of scope for this project, as documented in the project roadmap)

## 3. Functional requirements

1. A `docker-compose.yml` (or equivalent) must define at least three services: the Jenkins Controller, the Build/Test Agent, and the Docker Agent.
2. The Jenkins Controller must mount a named volume (`jenkins_home` or equivalent) to `/var/jenkins_home`, so plugins, configuration, and job history persist across container recreation.
3. The Build/Test Agent container must include a JDK version compatible with the project, Gradle (or the Gradle wrapper), and Git.
4. The Docker Agent container must include the Docker CLI (with access to a Docker daemon, e.g. via Docker-outside-of-Docker using the host's `/var/run/docker.sock`) and Git.
5. Both agents must connect to the Controller as inbound (JNLP) agents, each with a unique agent name and a dedicated, correctly configured secret.
6. The Controller must have the following plugins installed at minimum: Git, Pipeline, Credentials Binding, Docker Pipeline, and Configuration as Code.
7. After `docker compose up`, the Controller's built-in Nodes/Agents view must show both agents connected and marked as online.
8. Stopping and restarting the Docker Compose stack must not require re-entering the initial admin setup wizard or reinstalling plugins, confirming persistence works correctly.

## 4. Non-functional requirements

- CI gate: not applicable in this phase, since no pipeline logic exists yet; this phase is purely about infrastructure bootstrap.
- Security: the Docker Agent's access to the host Docker daemon (Docker-outside-of-Docker) must be understood and documented as a trust boundary — a compromised Docker Agent effectively has host-level Docker access, so this container must not be exposed or reused for anything beyond its intended CI role.
- Observability: Jenkins Controller and agent logs must be readable via `docker compose logs`, so connectivity issues between Controller and agents can be diagnosed without opening the Jenkins UI.

## 5. Acceptance criteria

- [x] `docker compose up` starts the Controller and both agents successfully
- [x] the Jenkins Controller UI is reachable on its configured port and completes initial setup without errors
- [x] both agents appear connected and online in the Controller's Nodes view
- [x] the Build/Test Agent can execute a simple `./gradlew --version` (or equivalent) command successfully when manually tested
- [x] the Docker Agent can execute a simple `docker version` command successfully when manually tested, confirming it can reach the Docker daemon
- [x] all required plugins (Git, Pipeline, Credentials Binding, Docker Pipeline, Configuration as Code) are installed and visible in the plugin manager
- [x] stopping and restarting the stack (`docker compose down` followed by `docker compose up`, without removing volumes) preserves Jenkins configuration and installed plugins

## 6. Deliverables

- code: `docker-compose.yml` (or a dedicated `jenkins/docker-compose.yml`) defining the Controller and both agents, plus any custom agent Dockerfiles needed to include the required tooling
- workflow: no GitHub Actions or `Jenkinsfile` changes in this phase (pipeline logic starts in Phase 15)
- documentation: a new `docs/jenkins.md` (or a section in `docs/architecture.md`) describing the Controller/Agent architecture, why agents are static rather than dynamic, and how to start/stop the local Jenkins stack

## 7. Evidence

- `docker compose ps` output showing the Controller and both agent containers running
- Jenkins Controller Nodes view output (or `docker exec` command output querying agent status) confirming both agents are online
- command output of `./gradlew --version` executed on the Build/Test Agent
- command output of `docker version` executed on the Docker Agent
- `docker compose down && docker compose up` log output confirming Jenkins started with existing configuration intact (no setup wizard re-triggered)

## 8. Risks and mitigations

- risk: giving the Docker Agent access to the host's Docker socket (Docker-outside-of-Docker) grants it effectively root-equivalent control over the host's Docker daemon, which is a meaningful security trade-off for convenience.
  mitigation: document this trade-off explicitly in `docs/jenkins.md`, restrict what runs on the Docker Agent to only the Docker build/push stages defined later, and avoid exposing this agent's capabilities to anything beyond the pipeline it is intended for.
- risk: forgetting to mount a persistent volume for the Controller would mean losing all configuration, plugins, and credentials every time the container is recreated.
  mitigation: treat the persistence check (stop/restart without losing configuration) as a blocking acceptance criterion, not an optional nice-to-have.
- risk: using two separate static agents (rather than one general-purpose agent) adds operational complexity — two containers to keep running and reconnect if they fail — for a project of this size.
  mitigation: accept this complexity deliberately, since it demonstrates a more realistic distributed CI/CD architecture, and document restart/reconnect steps clearly enough that recovering a disconnected agent is a known, quick procedure.
- risk: agent secrets (JNLP connection secrets) could be exposed if committed to version control or left in shell history.
  mitigation: generate agent secrets through the Controller's UI or API at setup time and keep them out of version control, treating them the same as any other credential.

## 9. Definition of done (phase)

- [x] implementation complete (Controller and both static agents running via Docker Compose, connected, with required plugins installed)
- [x] tests pass (manual verification that both agents can execute basic commands relevant to their role)
- [x] documentation updated (`docs/jenkins.md` describing the Controller/Agent setup and the static-agent rationale)
- [x] decisions recorded (e.g. Docker-outside-of-Docker vs. Docker-in-Docker for the Docker Agent, plugin set chosen) in `docs/decisions.md` or equivalent
